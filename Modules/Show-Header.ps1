function Show-Header {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Title
    )

    $width = 62
    $text = (' ' + $Title.Trim() + ' ')

    if ($text.Length -gt $width) {
        $text = $text.Substring(0, $width)
    }

    $padLeft = [Math]::Floor(($width - $text.Length) / 2)
    $padRight = $width - $text.Length - $padLeft

    $topBottom = '+' + ('-' * $width) + '+'
    $middle = '|' + (' ' * $padLeft) + $text + (' ' * $padRight) + '|'

    Write-Host $topBottom
    Write-Host $middle
    Write-Host $topBottom
}