param([Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PortablePath {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetShortPathName(string path, StringBuilder buffer, uint size);
}
'@
$buffer = New-Object Text.StringBuilder 32768
$length = [PortablePath]::GetShortPathName($Directory, $buffer, 32768)
if ($length -eq 0) { throw 'Cannot resolve the portable folder path.' }
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
[Console]::Write($buffer.ToString())
