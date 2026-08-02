# Lab 21 — Solutions

## Challenge A — multiple hung processes

**Check:**
```bash
ps -eo pid,ppid,stat,cmd | awk '$3 ~ /^D/'
```
Shows all three `dd` processes (and possibly `kworker` NFS I/O threads) in
`D` state, not just one. Also check the mount itself:
```bash
mountpoint -q /mnt/nfslab && echo mounted
cat /proc/mounts | grep nfslab
```

**Diagnosis:** every writer sharing the hung mount goes into `D` state
independently — there's no single "the" hung process, there's a hung
*mount*, and every process touching it at the time is a victim. This is
the real-world shape of NFS incidents: one alert says "process X is stuck,"
but X is a symptom, not the cause. Removing the `iptables` block fixes all
of them at once, because it fixes the shared underlying resource.

```bash
sudo iptables -D OUTPUT -p tcp --dport 2049 -j DROP
sudo iptables -D INPUT -p tcp --sport 2049 -j DROP
```
Give it a few seconds, then confirm all three PIDs exit on their own.

**Lesson:** when you find a D-state process, immediately check for siblings
on the same mount/device (`ps -eo pid,stat,cmd | awk '$2 ~ /^D/'`, `lsof
+D <mountpoint>`) before assuming it's an isolated problem — D-state
incidents are almost always resource-scoped, not process-scoped.

---

## Challenge B — the fix isn't instant

**Check:**
```bash
ps -o pid,stat,cmd -p <PID>
```
Run immediately after removing the `iptables` rules, the process can still
show `D` (or briefly `R` while the syscall finishes) for a few seconds
before it actually exits.

**Diagnosis:** removing the network block doesn't magically complete the
in-flight write — it just lets the retransmitted NFS request finally get a
response. The kernel still has to: get the RPC reply, finish the write
syscall, THEN notice the pending `SIGKILL` and act on it. All of that takes
real (if short) time, and depends on NFS retransmit/timeout timers that
were already counting up while blocked.

**Fix:** nothing further needed — just wait and re-check:
```bash
sleep 5
ps -o pid,stat,cmd -p <PID>
```

**Lesson:** "fixed the root cause" and "process is gone" are not the same
instant. Don't panic-escalate (e.g. reboot the box) just because a D-state
process is still visible a few seconds after you removed the block — give
the in-flight syscall a moment to actually unwind.
