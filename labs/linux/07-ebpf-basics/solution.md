# Lab 7 — Solutions

## Challenge A — a kprobe target that looks right but isn't

**Check:**
```bash
sudo bpftrace -e 'kprobe:sys_execve { printf("%d %s\n", pid, comm); }'
```
Fails with something like `Error: kprobe:sys_execve: probe not found` (or
a "no such kprobe/kallsyms entry" style error), rather than doing anything.

**Diagnosis:** on x86_64 Linux, raw syscall entry points are not named
plainly `sys_<name>` in the kernel symbol table. Since the syscall-entry
hardening work done for the Spectre/Meltdown-era mitigations, x86_64
syscall handlers are wrapped and exposed under names like
`__x64_sys_execve`, not `sys_execve`. `kprobe:sys_execve` targets a symbol
that simply doesn't exist on this architecture, so the probe fails to
attach. `tracepoint:syscalls:sys_enter_execve` (used in Step 2) doesn't
have this problem because tracepoints are a stable, architecture-
independent instrumentation point that the kernel maintains on purpose —
they don't depend on guessing internal function names.

**Fix:**
```bash
sudo bpftrace -lv 'kprobe:*execve*'
```
Find the actual symbol name on your kernel (e.g. `__x64_sys_execve`) and
use that instead, or — better — just use the tracepoint from Step 2, which
is the recommended approach specifically because it doesn't break across
kernel versions or architectures.

**Lesson:** kernel function names are not a stable ABI — they change with
architecture, compiler inlining decisions, and kernel version. Tracepoints
are a deliberately stable, documented interface; kprobes attach to whatever
symbol happens to exist right now. Prefer tracepoints over kprobes whenever
one exists for what you're trying to observe.

---

## Challenge B — the single most common first-run failure

**Check:**
```bash
bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("%s\n", comm); }'
```
Fails with a permission-related error (something like `Error:
BPF_PROG_LOAD failed: Operation not permitted`, possibly followed by a
hint about needing elevated privileges), not a syntax problem.

**Diagnosis:** loading an eBPF program into the kernel requires elevated
privileges — root, or at minimum specific capabilities
(`CAP_BPF`/`CAP_PERFMON`/`CAP_SYS_ADMIN` depending on kernel version and
what the program touches). Running `bpftrace` as a normal user has no path
to load anything; the kernel rejects the `bpf()` syscall used to load the
program before bpftrace ever gets to attach it to a probe.

**Fix:**
```bash
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("%s\n", comm); }'
```

**Lesson:** this is the single most common first-run mistake with
`bpftrace`/`bcc` tooling, and it's worth internalizing the error message
rather than pattern-matching "it didn't work" to a syntax problem — eBPF
program loading is a privileged kernel operation, full stop, regardless of
how simple the trace looks.
