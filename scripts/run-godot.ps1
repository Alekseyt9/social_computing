param(
	[string]$GodotCommand = "godot",
	[switch]$Editor,
	[switch]$Gpu
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $projectRoot ".env"

if (Test-Path -LiteralPath $envFile) {
	foreach ($line in Get-Content -LiteralPath $envFile) {
		$trimmed = $line.Trim()
		if (-not $trimmed -or $trimmed.StartsWith("#")) {
			continue
		}

		$name, $value = $trimmed.Split("=", 2)
		if ($name -in @("GROQ_API_KEY", "GROQ_MODEL")) {
			[Environment]::SetEnvironmentVariable($name, $value, "Process")
		}
	}
}

$godotArgs = @("--path", (Join-Path $projectRoot "game"))
if ($Editor) {
	$godotArgs = @("--editor") + $godotArgs
}
if ($Gpu) {
	$godotArgs += @("--rendering-method", "mobile")
}

& $GodotCommand @godotArgs
exit $LASTEXITCODE
