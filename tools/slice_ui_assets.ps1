param(
	[string]$SourceImage = "C:\Users\ex_sunhong\.codex\generated_images\019fb0f1-93d4-7fb0-bb94-01aae4a69fc2\call_ofP89dsHI4bdjNE3gCVGI20F.png",
	[string]$CleanBackground = "C:\Users\ex_sunhong\.codex\generated_images\019fb0f1-93d4-7fb0-bb94-01aae4a69fc2\call_dsx9euqOsUY4Tlf6PDds2awF.png",
	[string]$OutputDirectory = "assets\ui\xianxia_v3_slices"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$outputPath = Join-Path (Get-Location) $OutputDirectory
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

$source = [System.Drawing.Bitmap]::FromFile($SourceImage)

$slices = [ordered]@{
	"resource_energy_panel"       = @(172, 140, 166, 96)
	"resource_energy_icon"        = @(172, 142, 82, 94)
	"resource_energy_add_button"  = @(300, 194, 39, 42)
	"resource_qi_panel"           = @(336, 140, 182, 96)
	"resource_qi_icon"            = @(337, 143, 84, 91)
	"resource_qi_add_button"      = @(489, 194, 39, 42)
	"resource_stone_panel"        = @(520, 140, 190, 96)
	"resource_stone_icon"         = @(520, 141, 91, 95)
	"resource_stone_add_button"   = @(681, 194, 40, 42)
	"cultivator_character"        = @(24, 276, 208, 260)
	"cultivation_progress_frame"  = @(13, 522, 216, 66)
	"cultivation_reward_icon"     = @(169, 520, 64, 68)
	"order_left_frame"            = @(234, 375, 350, 214)
	"order_left_confirm_button"   = @(352, 465, 128, 63)
	"order_right_frame"           = @(594, 375, 259, 214)
	"order_right_confirm_button"  = @(683, 465, 130, 63)
	"board_frame"                 = @(6, 592, 838, 1072)
	"board_square_cell"           = @(36, 631, 105, 105)
	"item_detail_frame"           = @(123, 1665, 608, 177)
	"item_detail_title_tab"       = @(128, 1664, 192, 59)
	"item_info_button"            = @(266, 1664, 49, 53)
	"cultivation_button"          = @(12, 1676, 113, 166)
	"delete_button"               = @(604, 1710, 98, 112)
	"shop_button"                 = @(726, 1676, 118, 166)
}

$manifest = @()
foreach ($entry in $slices.GetEnumerator()) {
	$x, $y, $width, $height = $entry.Value
	$rect = [System.Drawing.Rectangle]::new($x, $y, $width, $height)
	$crop = $source.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$fileName = "$($entry.Key).png"
	$destination = Join-Path $outputPath $fileName
	$crop.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
	$crop.Dispose()

	$manifest += [ordered]@{
		name = $entry.Key
		file = $fileName
		x = $x
		y = $y
		width = $width
		height = $height
	}
}

$source.Dispose()

Copy-Item -LiteralPath $SourceImage -Destination (Join-Path $outputPath "ui_full_reference.png") -Force
Copy-Item -LiteralPath $CleanBackground -Destination (Join-Path $outputPath "background_clean.png") -Force

$manifestDocument = [ordered]@{
	source = "ui_full_reference.png"
	source_width = 853
	source_height = 1844
	background = "background_clean.png"
	slices = $manifest
}
$manifestDocument | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputPath "slices.json") -Encoding utf8

$contactColumns = 4
$contactCellWidth = 220
$contactCellHeight = 210
$contactRows = [Math]::Ceiling($slices.Count / $contactColumns)
$contactSheet = [System.Drawing.Bitmap]::new(
	$contactColumns * $contactCellWidth,
	$contactRows * $contactCellHeight,
	[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$graphics = [System.Drawing.Graphics]::FromImage($contactSheet)
$graphics.Clear([System.Drawing.Color]::FromArgb(255, 230, 234, 228))
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [System.Drawing.Font]::new("Arial", 10)
$textBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 42, 66, 58))

for ($index = 0; $index -lt $manifest.Count; $index++) {
	$item = $manifest[$index]
	$column = $index % $contactColumns
	$row = [Math]::Floor($index / $contactColumns)
	$cellX = $column * $contactCellWidth
	$cellY = $row * $contactCellHeight
	$imagePath = Join-Path $outputPath $item.file
	$image = [System.Drawing.Image]::FromFile($imagePath)
	$scale = [Math]::Min(180.0 / $image.Width, 160.0 / $image.Height)
	$drawWidth = [Math]::Max(1, [Math]::Round($image.Width * $scale))
	$drawHeight = [Math]::Max(1, [Math]::Round($image.Height * $scale))
	$drawX = $cellX + [Math]::Round(($contactCellWidth - $drawWidth) / 2)
	$drawY = $cellY + 8
	$graphics.DrawImage($image, $drawX, $drawY, $drawWidth, $drawHeight)
	$graphics.DrawString($item.name, $font, $textBrush, $cellX + 8, $cellY + 174)
	$image.Dispose()
}

$graphics.Dispose()
$font.Dispose()
$textBrush.Dispose()
$contactSheet.Save((Join-Path $outputPath "contact_sheet.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$contactSheet.Dispose()

Write-Output "Created $($slices.Count) UI slices in $outputPath"
