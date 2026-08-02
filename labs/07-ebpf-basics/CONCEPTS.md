# Lab 7 — Concept: eBPF, Tracepoints, and Why It's Not Just "strace But Faster"

## What's actually going on

eBPF lets you load a small, sandboxed program into the kernel that runs
when a specific event happens, without writing a kernel module and without
recompiling anything. `bpftrace` is a frontend that compiles the
one-liners you wrote (`tracepoint:syscalls:sys_enter_execve { ... }`) down
to BPF bytecode, asks the kernel to load it via the `bpf()` syscall, and
attaches it to the probe point you named. Before the kernel will run that
bytecode, the **BPF verifier** statically analyzes it: no unbounded loops,
every memory access provably in-bounds, every code path guaranteed to
terminate. This is the entire reason eBPF is allowed to run arbitrary
user-supplied logic inside the kernel at all — the verifier's job is to
make "arbitrary" mean "provably safe," not "trusted." Once verified, the
bytecode is usually JIT-compiled to native machine code, so the actual
runtime cost of a probe firing is close to a native function call, not an
interpreted loop.

The two attach mechanisms in this lab are genuinely different things,
which is exactly the point of Challenge A. A **tracepoint**
(`tracepoint:syscalls:sys_enter_execve`) is a static, deliberately placed
hook the kernel developers put directly in the source — it's a documented,
versioned, stable ABI with a defined format for its arguments (the `args.filename`
struct you used). A **kprobe** (`kprobe:sys_execve`) instead attaches to an
arbitrary kernel *function symbol* by patching in a breakpoint/trampoline
at that address — it depends entirely on a function with that exact name
existing in the currently running kernel's symbol table. On x86_64, the
syscall-entry hardening work around the Spectre/Meltdown era wrapped raw
syscall handlers under names like `__x64_sys_execve`, not `sys_execve` —
so a kprobe guessing the "obvious" name fails to attach, while the
tracepoint (which the kernel maintains as a stable interface on purpose,
independent of internal naming/inlining changes) keeps working across
architectures and kernel versions. This is why observability tooling
prefers tracepoints wherever one exists, and falls back to kprobes (or
newer fentry/fexit hooks, which are faster and equally robust) only when
nothing stable is exposed for the event you care about.

The aggregation step (Step 4) is the actual reason eBPF displaced
`strace`/`ptrace`-based tooling for production use. `strace` works by
stopping the traced process at every syscall entry/exit and copying the
full event to a separate debugger process — a context switch and a
userspace copy per event, which is why `strace -f` against a busy process
can slow it down by an order of magnitude or more. An eBPF map (`@[comm] =
count()`) lives entirely in kernel memory; the probe increments a counter
in-kernel on every hit and userspace only reads out the final aggregated
map once, at the end. The overhead per event is a few instructions, not a
context switch — this is what makes "always-on, production, every syscall"
observability viable in a way `ptrace` never was.

Finally, both eBPF program loading and reading most tracing data require
elevated privileges — loading code that runs inside the kernel is
inherently a privileged operation, gated by root or specific capabilities
(`CAP_BPF`, `CAP_PERFMON`, `CAP_SYS_ADMIN` depending on kernel version and
what the program does). This isn't a bpftrace-specific restriction; it's
enforced by the `bpf()` syscall itself before bpftrace ever gets to the
attach step, which is why Challenge B fails with a permissions error
rather than anything resembling a syntax problem.

## Where this shows up in the real world

Cilium replaces the iptables DNAT/REJECT rules you read by hand in Lab 6
with eBPF programs attached to the networking datapath (tc/XDP hooks),
enforcing NetworkPolicy and load-balancing without a single iptables rule.
Falco and Tetragon attach kprobes/tracepoints to exactly the kind of
events you traced here — `sys_enter_execve`, `tcp_connect` — to flag "a
shell was spawned inside this container" or "unexpected outbound
connection" in real time, in production, at a cost low enough to run on
every host. When a security or observability tool reports something is
happening "at the kernel level with near-zero overhead," this verifier +
in-kernel-aggregation model is what makes that claim literally true rather
than marketing.

## Go deeper

- **Book:** *Learning eBPF* — Liz Rice (O'Reilly, also free online via Isovalent) — the clearest from-scratch explanation of the verifier, program types, and maps.
- **Book:** *BPF Performance Tools* — Brendan Gregg — deep coverage of bpftrace/BCC tooling and exactly this tracepoint-vs-kprobe tradeoff.
- **Website:** eBPF official site — https://ebpf.io — background on program types, the verifier, and how Cilium/Falco/Tetragon are actually built on top of it.
- **Website/docs:** man7.org — https://man7.org/linux/man-pages/man7/bpf-helpers.7.html — plus `bpf(2)` for the syscall and privilege model this lab's Challenge B exercises.
- **YouTube:** eBPF / Isovalent — https://www.youtube.com/@eBPF — talks specifically on tracepoints vs kprobes, the verifier, and Cilium's datapath.
