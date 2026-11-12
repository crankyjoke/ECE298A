param(
    [string]$VivadoBin,
    [switch]$Waves
)

$ErrorActionPreference = 'Stop'

if (-not $VivadoBin -and $env:XILINX_VIVADO) {
    $VivadoBin = Join-Path $env:XILINX_VIVADO 'bin'
}
if (-not $VivadoBin) {
    $xvlogCommand = Get-Command xvlog.bat -ErrorAction SilentlyContinue
    if ($xvlogCommand) {
        $VivadoBin = Split-Path $xvlogCommand.Source -Parent
    }
}
if (-not $VivadoBin) {
    throw 'Specify -VivadoBin <Vivado installation>/bin, or run from a Vivado command prompt.'
}

$simulatorTools = @{}
foreach ($toolName in @('xvlog', 'xelab', 'xsim')) {
    $toolPath = Join-Path $VivadoBin "$toolName.bat"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        throw "Cannot find $toolPath"
    }
    $simulatorTools[$toolName] = (Resolve-Path -LiteralPath $toolPath).Path
}

$sourceDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
$sources = @('project.v', 'rsa_loader.v', 'rsa_modexp.v', 'rsa_modmul.v', 'rsa_alu.v') |
    ForEach-Object { Join-Path $sourceDirectory $_ }
$sources += Join-Path $PSScriptRoot 'tb_rsa.v'
$buildDirectory = Join-Path $PSScriptRoot 'sim_build/standalone_xsim'
New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
$tclPath = Join-Path $buildDirectory 'run.tcl'
$tclCommands = @()
if ($Waves) {
    $tclCommands += 'log_wave -r /'
}
$tclCommands += @('run all', 'quit')
Set-Content -LiteralPath $tclPath -Value $tclCommands -Encoding Ascii

Push-Location $buildDirectory
try {
    & $simulatorTools['xvlog'] --sv @sources
    if ($LASTEXITCODE -ne 0) { throw 'Verilog compilation failed.' }
    & $simulatorTools['xelab'] work.tb_rsa -s tb_rsa_snapshot -debug typical --timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw 'Testbench elaboration failed.' }
    Set-Content -LiteralPath 'simulate.log' -Value '' -Encoding Ascii
    & $simulatorTools['xsim'] tb_rsa_snapshot -tclbatch run.tcl -log simulate.log
    if ($LASTEXITCODE -ne 0) { throw 'RTL simulation failed.' }
    if (-not (Select-String -LiteralPath 'simulate.log' -SimpleMatch 'PASS: all RSA tests passed' -Quiet)) {
        throw 'Simulation did not reach the passing summary. Check test/sim_build/standalone_xsim/simulate.log.'
    }
} finally {
    Pop-Location
}
