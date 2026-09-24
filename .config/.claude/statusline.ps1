# Statusline script (PowerShell)
$ErrorActionPreference = 'SilentlyContinue'
$__input = [Console]::In.ReadToEnd()
try { $j = $__input | ConvertFrom-Json } catch { $j = $null }

# Terminal width for flex-spacer math. STATUSLINE_COLS env var overrides;
# else WindowWidth (throws on redirected stdout / CI), else 80.
$STATUSLINE_COLS = if ($env:STATUSLINE_COLS) {
  try { [int]$env:STATUSLINE_COLS } catch { 80 }
} else {
  try { [Console]::WindowWidth } catch { 80 }
}

# Visible-character length: strip CSI SGR sequences then .Length.
# Wide glyphs (emoji, CJK) count as 1 column.
function __visibleLen([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return 0 }
  $stripped = $s -replace "$([char]27)\[[0-9;]*m", ''
  return $stripped.Length
}

function __get($obj, [string]$path) {
  if ($null -eq $obj -or [string]::IsNullOrEmpty($path)) { return '' }
  $cur = $obj
  foreach ($p in $path.Split('.')) {
    if ($null -eq $cur) { return '' }
    $prop = $cur.PSObject.Properties[$p]
    if ($null -eq $prop) { return '' }
    $cur = $prop.Value
  }
  if ($null -eq $cur) { return '' }
  return $cur
}

function __field([string]$path) { [string](__get $j $path) }
function __sgr([string]$codes) {
  if ([string]::IsNullOrEmpty($codes)) { return '' }
  return "$([char]27)[${codes}m"
}
function __reset() { return "$([char]27)[0m" }

# Output sink: when $__SINK is non-null, __emit/__write append to it
# (used for flex-spacer chunk capture). Otherwise bytes go straight to the
# raw standard-output stream as UTF-8.
#
# We deliberately bypass [Console]::Out.Write: that re-encodes through
# [Console]::OutputEncoding, which on Windows PowerShell 5.1 defaults to the
# console's OEM code page (e.g. IBM437 / CP1252). Those code pages can't
# represent the block-bar glyphs, box drawing, or emoji a statusline may emit,
# so they get mangled to '?' regardless of the terminal's own encoding. Writing
# UTF-8 bytes straight to the handle is independent of the console code page AND
# of host color handling. The compiled body below keeps all literals ASCII
# (non-ASCII is emitted as [char] escapes) so the in-memory strings are correct
# even when PowerShell 5.1 parses this BOM-less file as its OEM code page.
$__SINK = $null
$__stdout = [Console]::OpenStandardOutput()
function __write([string]$text) {
  if ($null -eq $script:__SINK) {
    $__b = [System.Text.Encoding]::UTF8.GetBytes($text)
    $script:__stdout.Write($__b, 0, $__b.Length)
  } else { $script:__SINK.Append($text) | Out-Null }
}
function __emit([string]$codes, [string]$text) {
  $out = ''
  if ($codes) { $out += __sgr $codes }
  $out += $text
  if ($codes) { $out += __reset }
  __write $out
}
function __basename([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $idx = [Math]::Max($s.LastIndexOf('/'), $s.LastIndexOf('\'))
  if ($idx -ge 0) { return $s.Substring($idx + 1) } else { return $s }
}
function __compact([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $sep = '/'
  if (($s.IndexOf('\') -ge 0) -and ($s.IndexOf('/') -lt 0)) { $sep = '\' }
  $leading = ''
  $body = $s
  if ($s.StartsWith($sep)) { $leading = $sep; $body = $s.Substring(1) }
  if ($body -eq '') { return $leading }
  $parts = $body -split [regex]::Escape($sep)
  if ($parts.Length -le 1) { return $s }
  $last = $parts[$parts.Length - 1]
  $collapsed = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $parts.Length - 1; $i++) {
    $seg = $parts[$i]
    if ([string]::IsNullOrEmpty($seg)) { $collapsed.Add('') }
    else { $collapsed.Add($seg.Substring(0, 1)) }
  }
  $collapsed.Add($last)
  return $leading + ($collapsed -join $sep)
}
function __tildify([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $h = $env:USERPROFILE
  if (-not $h) { $h = $env:HOME }
  if ($h -and $s.StartsWith($h)) { return '~' + $s.Substring($h.Length) }
  return $s
}
function __truncate([string]$s, [int]$n) {
  if ($n -le 0 -or $s.Length -le $n) { return $s }
  if ($n -le 1) { return $s.Substring(0, $n) }
  return $s.Substring(0, $n - 1) + [char]0x2026
}
function __costFmt([string]$v, [int]$prec) {
  $n = 0.0
  [double]::TryParse($v, [ref]$n) | Out-Null
  return '$' + $n.ToString('F' + $prec)
}
function __durHms([string]$v) {
  $ms = 0; [int64]::TryParse($v, [ref]$ms) | Out-Null
  $total = [int]([math]::Floor($ms / 1000))
  $h = [math]::Floor($total / 3600)
  $m = [math]::Floor(($total % 3600) / 60)
  $s = $total % 60
  if ($h -gt 0) { return ('{0}:{1:D2}:{2:D2}' -f $h, $m, $s) }
  return ('{0}:{1:D2}' -f $m, $s)
}
function __durHuman([string]$v) {
  $ms = 0; [int64]::TryParse($v, [ref]$ms) | Out-Null
  $total = [int]([math]::Floor($ms / 1000))
  if ($total -lt 60) { return ('{0}s' -f $total) }
  $m = [math]::Floor($total / 60); $s = $total % 60
  if ($m -lt 60) { if ($s -gt 0) { return ('{0}m {1}s' -f $m, $s) } else { return ('{0}m' -f $m) } }
  $h = [math]::Floor($m / 60); $mm = $m % 60
  if ($mm -gt 0) { return ('{0}h {1}m' -f $h, $mm) } else { return ('{0}h' -f $h) }
}
function __bar([string]$v, [int]$width, [string]$filled, [string]$empty) {
  $p = 0.0; [double]::TryParse($v, [ref]$p) | Out-Null
  if ($p -lt 0) { $p = 0 } elseif ($p -gt 100) { $p = 100 }
  $n = [int][math]::Round(($p * $width) / 100)
  $e = $width - $n
  return ($filled * $n) + ($empty * $e)
}
function __normInt([string]$v) {
  if ([string]::IsNullOrEmpty($v)) { return 0 }
  $idx = $v.IndexOf('.')
  if ($idx -ge 0) { $v = $v.Substring(0, $idx) }
  $n = 0
  if (-not [int64]::TryParse($v, [ref]$n)) { return 0 }
  if ($n -lt 0) { return 0 }
  return $n
}
function __fmtTokenCompact([string]$v) {
  $n = __normInt $v
  if ($n -lt 1000) { return [string]$n }
  if ($n -lt 1000000) {
    $whole = [math]::Floor($n / 1000)
    $rem = $n - ($whole * 1000)
    $dec = [math]::Floor($rem / 100)
    if ($dec -eq 0) { return ('{0}k' -f $whole) }
    return ('{0}.{1}k' -f $whole, $dec)
  }
  $whole = [math]::Floor($n / 1000000)
  $rem = $n - ($whole * 1000000)
  $dec = [math]::Floor($rem / 100000)
  if ($dec -eq 0) { return ('{0}M' -f $whole) }
  return ('{0}.{1}M' -f $whole, $dec)
}
function __fmtTokenFull([string]$v) {
  $n = __normInt $v
  return $n.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
}
function __tokensUsed() { __field 'context_window.total_input_tokens' }
function __tokensTotal() { __field 'context_window.context_window_size' }
function __tokensRemaining() {
  $u = __normInt (__tokensUsed)
  $t = __normInt (__tokensTotal)
  $r = $t - $u
  if ($r -lt 0) { $r = 0 }
  return [string]$r
}
function __tokensPctInt() {
  $p = __field 'context_window.used_percentage'
  return [string](__normInt $p)
}
function __gitBranch() {
  $cwd = __field 'workspace.current_dir'
  if (-not $cwd) { $cwd = __field 'cwd' }
  if ($cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $b = & git -C "$cwd" rev-parse --abbrev-ref HEAD 2>$null
    if ($b) { return $b.Trim() }
  }
  return __field 'workspace.git_worktree'
}
function __gitDirty() {
  $cwd = __field 'workspace.current_dir'
  if (-not $cwd) { $cwd = __field 'cwd' }
  if ($cwd -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $s = & git -C "$cwd" status --porcelain 2>$null
    if ($s) { return '1' }
  }
  return '0'
}
function __tick() {
  if ($env:STATUSLINE_CLOCK_OVERRIDE) {
    $o = 0
    if ([int64]::TryParse($env:STATUSLINE_CLOCK_OVERRIDE, [ref]$o)) { return $o }
  }
  return [DateTimeOffset]::Now.ToUnixTimeSeconds()
}
function __relTime([string]$v) {
  if ([string]::IsNullOrEmpty($v)) { return '' }
  $target = 0.0
  if (-not [double]::TryParse($v, [ref]$target)) { return '' }
  $now = __tick
  $diff = [int]([math]::Floor($target - $now))
  if ($diff -le 0) { return '' }
  if ($diff -lt 60) { return ('T-{0}s' -f $diff) }
  if ($diff -lt 3600) {
    $m = [math]::Floor($diff / 60); $s = $diff % 60
    return ('T-{0}m{1:D2}s' -f $m, $s)
  }
  $h = [math]::Floor($diff / 3600); $rem = [math]::Floor(($diff % 3600) / 60)
  return ('T-{0}h{1:D2}m' -f $h, $rem)
}

__emit '1;38;2;192;202;245;49' ' '
__emit '1;38;2;192;202;245;49' (__field 'model.display_name')
__emit '1;38;2;192;202;245;49' ' '
if (((__field 'thinking.enabled') -eq 'true')) {
  __emit '1;38;2;154;165;206' (__field 'effort.level')
}
__emit '38;2;192;202;245;49' ' / '
__emit '2;38;2;192;202;245' 'tok '
__emit '1;38;2;192;202;245' ((__fmtTokenCompact (__tokensUsed)) + '/' + (__fmtTokenCompact (__tokensTotal)) + ' (' + (__tokensPctInt) + '%)')
__emit '1;38;2;192;202;245' ' '
__emit '38;2;192;202;245' (__bar (__field 'context_window.used_percentage') 34 ([char]0x25AA) ([char]0xB7))
__emit '38;2;192;202;245' ' '
__emit '1;38;2;192;202;245' (__costFmt (__field 'cost.total_cost_usd') 2)
__write ((__reset) + "`n" + (__reset))
__emit '2;38;2;192;202;245' ' usage  '
__emit '1;38;2;154;165;206' '5h '
__emit '38;2;192;202;245' (__bar (__field 'rate_limits.five_hour.used_percentage') 30 ([char]0x25AA) ([char]0xB7))
__emit '38;2;192;202;245' ' '
__emit '1;38;2;154;165;206' '7d '
__emit '38;2;192;202;245' (__bar (__field 'rate_limits.seven_day.used_percentage') 30 ([char]0x25AA) ([char]0xB7))
__emit '38;2;192;202;245' ' '
__write ((__reset) + "`n" + (__reset))
__emit '1;38;2;192;202;245' ' '
__emit '1;38;2;192;202;245' (__basename (__field 'workspace.current_dir'))
__emit '38;2;192;202;245' ' / '
__emit '1;38;2;192;202;245' (__gitBranch)
__emit '38;2;192;202;245' ' / '
__emit '2;38;2;192;202;245' 'dur '
__emit '1;38;2;154;165;206' (__durHuman (__field 'cost.total_duration_ms'))
__emit '38;2;192;202;245' ' / '
__emit '38;2;158;206;106' '+'
__emit '38;2;158;206;106' (__field 'cost.total_lines_added')
__emit '38;2;65;72;104' ' ~ '
__emit '38;2;247;118;142' '-'
__emit '38;2;247;118;142' (__field 'cost.total_lines_removed')

$__stdout.Flush()
