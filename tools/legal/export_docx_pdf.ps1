param([Parameter(Mandatory=$true)][string]$SourcePath, [Parameter(Mandatory=$true)][string]$PdfPath)
$ErrorActionPreference = 'Stop'
$wordApplication = $null
$wordDocument = $null
try {
    $wordApplication = New-Object -ComObject Word.Application
    $wordApplication.Visible = $false
    $wordApplication.DisplayAlerts = 0
    $wordApplication.AutomationSecurity = 3
    $wordDocument = $wordApplication.Documents.Open($SourcePath, $false, $true, $false)
    [void]$wordDocument.Fields.Update()
    $wordDocument.ExportAsFixedFormat($PdfPath, 17)
    Write-Output 'Rendered read-only DOCX with native Microsoft Word.'
} finally {
    $saveOption = 0
    if ($null -ne $wordDocument) {
        $wordDocument.Close([ref]$saveOption)
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($wordDocument)
    }
    if ($null -ne $wordApplication) {
        $wordApplication.Quit([ref]$saveOption)
        [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($wordApplication)
    }
}
