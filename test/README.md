# RSA testbenches

The implemented top module is `tt_um_example`. There are two independent ways
to test it:

- `tb_rsa.v`: self-checking standalone RTL testbench for Vivado XSim or Icarus
  Verilog. It needs no cocotb installation.
- `tb.v` and `test.py`: the existing cocotb RTL/gate-level regression.

## Standalone testbench

`tb_rsa.v` drives only the external pins and compares both 14-bit output pages
against a 64-bit software-style modular-exponentiation function. It checks:

- The eight 7-bit input chunks, least-significant chunk first: four for `N`,
  two for `e`, and two for `m`.
- The known RSA example `65^17 mod 3233 = 2790`, zero exponent, zero message,
  minimum/maximum supported widths, and 200 reproducible random vectors.
- Fixed `uio_oe = 0x7f`, zero result pins before DONE, and both page-selection
  directions after DONE.
- Ignored early START edges, LOAD/START edges while disabled, long strobes,
  and extra LOAD/START edges after loading or completion.
- Enable pause/resume, including comparison of enabled-cycle latency with an
  uninterrupted computation.
- Reset during partial loading, active computation, and while disabled;
  asynchronous clearing of DONE; and result retention until reset.

Valid inputs are `2 <= N < 2^28`, `0 <= e < 2^14`, and
`0 <= m < min(N, 2^14)`. Unsupported inputs are not assigned expected results.
This is functional RTL verification; the 10 ns simulation clock does not
establish a hardware timing limit or model analog metastability.

Successful completion prints `PASS: all RSA tests passed (218 transactions)`.
Any mismatch or timeout calls `$fatal`. Waveforms are optional to keep the
full regression small.

### Vivado on Windows

From the repository root, using your Vivado installation directory:

```powershell
powershell -ExecutionPolicy Bypass -File test/run_xsim.ps1 -VivadoBin 'D:\Xillinx\Vivado\2021.2\bin'
```

`-VivadoBin` can be omitted if `xvlog.bat` is on PATH or `XILINX_VIVADO` is set.
Add `-Waves` to log signals into XSim's waveform database. Compilation logs,
the simulation log, and the waveform database are written under
`test/sim_build/standalone_xsim/`.

In the Vivado GUI, add the five RSA files from `src/` as design sources and
`tb_rsa.v` as a simulation source. Set the simulation top to **`tb_rsa`** and
choose **Run All**. The cocotb harness `tb.v` does not generate its own stimulus.
The RTL files do not declare timescales; set XSim's additional elaboration
options to `--timescale 1ns/1ps` if needed. The PowerShell runner sets this.

### Icarus Verilog

From the `test/` directory:

```sh
mkdir -p sim_build/standalone
iverilog -g2012 -s tb_rsa -o sim_build/standalone/tb_rsa.vvp \
  ../src/project.v ../src/rsa_loader.v ../src/rsa_modexp.v \
  ../src/rsa_modmul.v ../src/rsa_alu.v tb_rsa.v
vvp sim_build/standalone/tb_rsa.vvp
```

To write `rsa.vcd` for GTKWave or Surfer, append `+WAVES` to the `vvp` command.

## Cocotb regression

Install Icarus Verilog, make, and the Python dependencies, then run from `test/`:

```sh
python -m pip install -r requirements.txt
make -B
```

This runs the existing 10 fixed and 200 random vectors against Python's
`pow(m, e, N)`, using the separate top module `tb`.

For gate-level simulation, first copy the hardened `tt_um_example` netlist to
`test/gate_level_netlist.v`, set `PDK_ROOT` to the GF180 PDK, and run:

```sh
make -B GATES=yes
```

The cocotb harness writes `tb.fst`, viewable with either:

```sh
gtkwave tb.fst tb.gtkw
surfer tb.fst
```
