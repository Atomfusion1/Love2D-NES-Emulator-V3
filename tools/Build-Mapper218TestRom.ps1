$ErrorActionPreference = 'Stop'

$code = [System.Collections.Generic.List[byte]]::new()
$labels = @{}
$fixups = [System.Collections.Generic.List[object]]::new()

function Emit([int[]] $bytes) { foreach ($byte in $bytes) { [void]$script:code.Add([byte]$byte) } }
function Label([string] $name) { $script:labels[$name] = $script:code.Count }
function Abs([int] $opcode, [string] $name) {
    Emit @($opcode, 0, 0)
    $script:fixups.Add([pscustomobject]@{ Offset = $script:code.Count - 2; Name = $name })
}
function Branch([int] $opcode, [string] $name) {
    Emit @($opcode, 0)
    $script:fixups.Add([pscustomobject]@{ Offset = $script:code.Count - 1; Name = $name; Branch = $true; Origin = $script:code.Count })
}

# Reset: disable rendering, wait for vblank, upload palette/CHR/nametable data.
Label 'reset'
Emit @(0x78, 0xD8, 0xA2, 0x40, 0x8E, 0x17, 0x40, 0xA2, 0xFF, 0x9A)
Emit @(0xE8, 0x8E, 0x00, 0x20, 0x8E, 0x01, 0x20, 0x8E, 0x10, 0x40)
Abs 0x20 'wait_vblank'
Abs 0x20 'write_palette'
Abs 0x20 'write_chr'
Abs 0x20 'write_nametable'
Emit @(0xA9, 0x00, 0x8D, 0x00, 0x20, 0xA9, 0x1A, 0x8D, 0x01, 0x20)
Label 'forever'
Abs 0x4C 'forever'

Label 'wait_vblank'
Label 'wait_vblank_loop'
Emit @(0x2C, 0x02, 0x20)
Branch 0x10 'wait_vblank_loop'
Emit @(0x60)

Label 'write_palette'
Emit @(0xA9, 0x3F, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0x8D, 0x06, 0x20)
Emit @(0xA2, 0x00)
Label 'palette_loop'
Emit @(0xBD, 0, 0, 0x8D, 0x07, 0x20, 0xE8)
$fixups.Add([pscustomobject]@{ Offset = $code.Count - 6; Name = 'palette'; AbsoluteX = $true })
Emit @(0xE0, 0x10)
Branch 0xD0 'palette_loop'
Emit @(0x60)

Label 'write_chr'
Emit @(0xA9, 0x00, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0x8D, 0x06, 0x20, 0xA2, 0x00)
Label 'chr_loop'
Emit @(0xBD, 0, 0, 0x8D, 0x07, 0x20, 0xE8)
$fixups.Add([pscustomobject]@{ Offset = $code.Count - 6; Name = 'chr_data'; AbsoluteX = $true })
Emit @(0xE0, 0x80)
Branch 0xD0 'chr_loop'
Emit @(0x60)

Label 'write_nametable'
Emit @(0xA9, 0x20, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0x8D, 0x06, 0x20, 0xA9, 0x00, 0xA2, 0x03)
Label 'nt_page'
Emit @(0xA0, 0x00)
Label 'nt_page_loop'
Emit @(0x8D, 0x07, 0x20, 0x88)
Branch 0xD0 'nt_page_loop'
Emit @(0xCA)
Branch 0xD0 'nt_page'
Emit @(0xA0, 0xC0)
Label 'nt_tail'
Emit @(0x8D, 0x07, 0x20, 0x88)
Branch 0xD0 'nt_tail'

# Put the test label "218!" on row 14, column 14.
Emit @(0xA9, 0x21, 0x8D, 0x06, 0x20, 0xA9, 0xC0, 0x8D, 0x06, 0x20)
Emit @(0xA2, 0x01)
Label 'message_loop'
Emit @(0x8E, 0x07, 0x20, 0xE8)
Emit @(0xE0, 0x05)
Branch 0xD0 'message_loop'
Emit @(0x60)

Label 'palette'
Emit @(0x0F, 0x16, 0x27, 0x30, 0x0F, 0x16, 0x27, 0x30, 0x0F, 0x16, 0x27, 0x30, 0x0F, 0x16, 0x27, 0x30)

Label 'chr_data'
# Tile 0 blank, tiles 1-4 are 2, 1, 8, !. Remaining bytes are blank.
$tiles = @(
    @(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),
    @(0x7E,0x81,0x01,0x06,0x18,0x60,0xFF,0,0,0,0,0,0,0,0,0),
    @(0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0,0,0,0,0,0,0,0,0),
    @(0x7E,0x81,0x81,0x7E,0x81,0x81,0x7E,0,0,0,0,0,0,0,0,0),
    @(0x18,0x18,0x18,0x18,0x18,0,0x18,0,0,0,0,0,0,0,0,0)
)
foreach ($tile in $tiles) { Emit $tile }
Emit ([int[]](0..127 | ForEach-Object { 0 }))

# Patch all label references.
foreach ($fixup in $fixups) {
    if (-not $labels.ContainsKey($fixup.Name)) { throw "Unknown label $($fixup.Name)" }
    $target = $labels[$fixup.Name]
    if ($fixup.Branch) {
        $relative = $target - $fixup.Origin
        if ($relative -lt -128 -or $relative -gt 127) { throw "Branch out of range: $($fixup.Name)" }
        $code[$fixup.Offset] = [byte]($relative -band 0xFF)
    } elseif ($fixup.AbsoluteX) {
        $address = 0x8000 + $target
        $code[$fixup.Offset] = [byte]($address -band 0xFF)
        $code[$fixup.Offset + 1] = [byte](($address -shr 8) -band 0xFF)
    } else {
        $address = 0x8000 + $target
        $code[$fixup.Offset] = [byte]($address -band 0xFF)
        $code[$fixup.Offset + 1] = [byte](($address -shr 8) -band 0xFF)
    }
}

if ($code.Count -gt 0x3FFA) { throw "Test program is too large: $($code.Count) bytes" }
$prg = [System.Collections.Generic.List[byte]]::new()
$prg.AddRange($code)
while ($prg.Count -lt 0x3FFA) { [void]$prg.Add(0) }
$resetAddress = 0x8000 + $labels['reset']
foreach ($vector in @($resetAddress, $resetAddress, $resetAddress)) {
    [void]$prg.Add([byte]($vector -band 0xFF))
    [void]$prg.Add([byte](($vector -shr 8) -band 0xFF))
}

# iNES: 16 KiB PRG, no CHR-ROM, Mapper 218 A12 wiring ($A8/$D0).
$rom = [System.Collections.Generic.List[byte]]::new()
$rom.AddRange([byte[]](0x4E,0x45,0x53,0x1A,0x01,0x00,0xA8,0xD0,0,0,0,0,0,0,0,0))
$rom.AddRange($prg)
$output = Join-Path $PSScriptRoot '..\Roms\Mapper218-Test-218.NES'
[System.IO.File]::WriteAllBytes((Resolve-Path (Join-Path $PSScriptRoot '..')).Path + '\Roms\Mapper218-Test-218.NES', $rom.ToArray())
Write-Output "Wrote $output ($($rom.Count) bytes)"
