# Lab 7 — eBPF Basics

## Objective
Use `bpftrace` to trace real kernel events — process execs and TCP
connects — and see why eBPF underlies modern observability and security
tooling (Cilium, Falco, Pixie, Tetragon).

## Why this matters
Cilium replaces iptables-based kube-proxy (the exact rules you read by hand
in Lab 6) with eBPF programs attached to the networking datapath. Falco and
Tetragon detect suspicious container behavior (a shell spawned inside a
container, an unexpected outbound connection) by attaching eBPF probes to
the same tracepoints/kprobes this lab uses directly. Once you've traced a
syscall by hand with `bpftrace`, "eBPF-powered" tooling stops being a black
box.

## Prerequisites
- `bpftrace`
- kernel with BTF support (most modern Ubuntu kernels have this built in)

Check first:
```bash
sudo apt-get update && sudo apt-get install -y bpftrace
bpftrace --version
uname -r
ls /sys/kernel/btf/vmlinux 2>/dev/null || echo "no BTF — some probes may need extra setup"
```

## Step 1 — List available probes
```bash
sudo bpftrace -l 'tracepoint:syscalls:sys_enter_execve'
sudo bpftrace -lv tracepoint:syscalls:sys_enter_execve
```
The `-lv` output shows the tracepoint's actual fields — you'll need
`filename` in the next step.

## Step 2 — Trace every process exec
```bash
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("%s -> %s\n", comm, str(args.filename)); }'
```
> Gotcha: `args.filename` (dot syntax) is the current bpftrace field-access
> syntax. Older bpftrace versions (as shipped on some older LTS distro
> repos) use `args->filename` (arrow syntax) instead. If you get a parse
> error, try the arrow form.

Leave this running, and in a second terminal run a few ordinary commands
(`ls`, `whoami`, `curl -s example.com > /dev/null`). Watch them appear
live in the first terminal. Ctrl-C to stop.

## Step 3 — Trace TCP connect attempts
```bash
sudo bpftrace -e 'kprobe:tcp_connect { printf("PID %d (%s) attempting TCP connect\n", pid, comm); }'
```
In a second terminal:
```bash
curl -s http://example.com > /dev/null
nc -zv 1.1.1.1 443
```
Watch each connection attempt fire in the first terminal. This is the
exact primitive `tcpconnect`-style tools (bpftrace ships one at
`/usr/share/bpftrace/tools/tcpconnect.bt` on most distro packages) are
built on, and conceptually what Cilium hooks to enforce L3/L4 network
policy without touching iptables at all.

## Step 4 — Aggregate in-kernel (the actual point of eBPF)
```bash
sudo bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); } interval:s:5 { print(@); exit(); }'
```
This counts every syscall by process name, in the kernel, for 5 seconds,
then prints one summary. Compare this mentally to `strace`: `strace` copies
EVERY traced event to userspace one at a time (huge overhead, and it's why
you'd never run `strace -f` against a busy production process); this
one-liner aggregates entirely inside the kernel and only ever hands
userspace the final map. That difference in overhead is the whole reason
eBPF-based tooling (Cilium, Falco, Pixie) is viable for always-on production
observability where `strace`/`ptrace`-based tooling isn't.

## Step 5 — Tie it together
- Cilium: eBPF programs on the networking datapath (tc/XDP hooks) replace
  the iptables DNAT/REJECT rules you read by hand in Lab 6.
- Falco / Tetragon: attach kprobes/tracepoints like `sys_enter_execve` (Step
  2) to flag things like "a shell was exec'd inside this container" in
  real time, in production, with minimal overhead.

## Challenges (don't read ahead — diagnose before you fix)

**Challenge A — a kprobe target that looks right but isn't:**
```bash
sudo bpftrace -e 'kprobe:sys_execve { printf("%d %s\n", pid, comm); }'
```
This looks like it should obviously work — it's just the syscall name.
Check what error you actually get, then check `/proc/kallsyms` (or
`sudo bpftrace -l 'kprobe:*execve*'`) for what the real underlying kernel
symbol is called on this machine. Figure out why kernel function names
aren't a reliable naming convention to guess at, and why Step 2 used a
tracepoint instead of a kprobe for this exact same event.

**Challenge B — the single most common first-run failure:**
```bash
bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("%s\n", comm); }'
```
(No `sudo`.) Read the actual error message carefully — it's not a syntax
error.

See `SOLUTION.md` only after you've formed your own diagnosis.
