<# Posiflex.ps1 - Extract data from the XML file

This function extracts data from an XML file after validating the 
XML file against the Schema file in the path given.

Output -
  The extracted data will be stored in the following tables of the
  LabTech database:
	hpf_posiflex
	hpf_cashregister
	hpf_epsonprinter
	hpf_poledisplay
	hpf_receiptprinter
	hpf_stripereader

Syntax -
	The parameters are optional. The generalized format is:
	./posiflex.ps1 [<FilePath>] [<XML_Filename>] [<XSD_Filename>]
	
	Examples:
	
		./posiflex.ps1

		./posiflex.ps1 C:\Posiflex\RMM RMM.xml RMM.xsd

#>
param(
	[parameter(Position=0,Mandatory=$false,ValueFromPipeline=$false,HelpMessage='Path to Posiflex files')][string]$Path="C:\Posiflex\RMM",
	[parameter(Position=1,Mandatory=$false,ValueFromPipeline=$false,HelpMessage='Filename of Posiflex XML file')][string]$XMLFileName="RMM.xml",
	[parameter(Position=2,Mandatory=$false,ValueFromPipeline=$false,HelpMessage='Filename of Posiflex XSD file')][string]$XSDFileName="RMM.xsd"
)

 	#Variable Declarations

    $ErrorActionPreference = "SilentlyContinue"
    $FailCount = 0
	$CR = ''
	$MSR = ''
	$PD = ''
	$Epson = ''
	$Printer = ''
	$CRvalues = ''
	$MSRvalues = ''
	$PDvalues = ''
	$Epsonvalues = ''
	$Printervalues = ''

<# Verify that the path and files are valid #>
if (!(test-path -Path $PATH\$XMLFileName))
  {
	$ErrorMessage = "Problem: XML File Not Found"
	Write-Output $ErrorMessage 
	Exit
  }

if (!(test-path $PATH\$XSDFileName))
  {
	$ErrorMessage = "Problem: XSD File Not Found"
	Write-Output $ErrorMessage 
	Exit
  }

<# First make sure the Schema is good #>

	$readerSettings = New-Object -TypeName System.Xml.XmlReaderSettings
	$readerSettings.ValidationType = [System.Xml.ValidationType]::Schema
	$readerSettings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessInlineSchema -bor
		[System.Xml.Schema.XmlSchemaValidationFlags]::ProcessSchemaLocation -bor 
		[System.Xml.Schema.XmlSchemaValidationFlags]::ReportValidationWarnings
			
	try {
            $readerSettings.Schemas.Add($null, "$PATH\$XSDFileName") | Out-Null
	}
	catch {
	    # Exception on validation
	    $ErrorMessage = "Problem: The schema file is not well formed.`r`n`r`n" + $_.Exception.message
		Write-Output $ErrorMessage 
	    Exit
	}
 
<# Then make sure the XML is good #>
  		
	Try{
		# Load xml and add schema
		$Context = [xml](Get-Content "$PATH\$XMLFileName")
		$Context.Schemas.Add($null, "$PATH\$XSDFileName") | Out-Null
	}
	Catch{
		$ErrorMessage = "Problem: Failed to create XML object"
		Write-Output $ErrorMessage 
		Exit
	}
		
    # Validate xml against schema
	$Context.Validate({
		$FailCount = 1
		$ErrorMessage = "Problem: The XML file is not well formed.`r`n`r`n" + $_.Exception.Message
	})
	If ($FailCount -eq 1) {
		Write-Output $ErrorMessage
		Exit
	}

		
<# Parse the XML file. #>

[xml]$rms = Get-Content $PATH\$XMLFileName

Try {
	$xpath = '/RMS_INFO/Log_Time_Part/Log[1]/@Date'
	$LogDate = (Select-Xml -XPath $xpath -Xml $rms).ToString() | ForEach-Object {$_.Substring(0,10)}
}Catch {
	$Output = "Problem: Failed to read the log date from XML file."
	Write-Output $Output
	Break
}

Try {
	$xpath = '/RMS_INFO/Log_Time_Part/Log[2]/@Time'
	$LogTime = (Select-Xml -XPath $xpath -Xml $rms).ToString()
}Catch {
	$Output = "Problem: Failed to read the log time data from XML file."
	Write-Output $Output
	Break
}

#EndDate is used to calculate Printer Age
$EndDate = [datetime]::ParseExact($logdate,"yyyy/MM/dd",$null)

#EntryDate is the record date entered into the database
$EntryDate = "$LogDate $LogTime"

#Parse Posiflex Devices

<#	This section will be run extract Cash Register data from the XML. It
	#runs through a for loop which pulls information from the XML for each of
	#the cash register attributes. #> 

For ($I=1;$I -Le 5; $I++){
	#The maximum number of peripherals was 5 so that's as high as the For Loop is allowed to go.

	Try {
		$xpath = '/RMS_INFO/POS_USB_CR'+$I+'_Part/POS_USB_CR'+$I+'[8]/@CR_Status'
		$CR_Status = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_CR'+$I+'_Part/POS_USB_CR'+$I+'[2]/@ModelName'
		$CR_ModelName = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_CR'+$I+'_Part/POS_USB_CR'+$I+'[7]/@DrawerFailedOpenCount'
		$CR_DrawerFailedOpenCount=(Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_CR'+$I+'_Part/POS_USB_CR'+$I+'[1]/@PID'
		$CR_PID = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_CR'+$I+'_Part/POS/@USB_CR'+$I+'_CFG'
		$CR_Config =(Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}	
	Try {         
		$xpath = '/RMS_INFO/POS_USB_CR'+$I+'_Part/POS_USB_CR'+$I+'[4]/@ManufactureDate'
		$CR_ManufactureDate =(Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}
	IF ($CRvalues -eq '') {
		$CRvalues = " VALUES(`'@PosiflexID@`',`'$I`',`'$CR_Config1`',`'$CR_DrawerFailedOpenCount`',`'$CR_ModelName`',`'$CR_PID`',`'$CR_Status`',`'@NewRecordNumber@`',`'$CR_ManufactureDate`',`'$EntryDate`')" 
	}Else{
		$CRvalues = $CRvalues + ",(`'@PosiflexID@`',`'$I`',`'$CR_Config1`',`'$CR_DrawerFailedOpenCount`',`'$CR_ModelName`',`'$CR_PID`',`'$CR_Status`',`'@NewRecordNumber@`',`'$CR_ManufactureDate`',`'$EntryDate`')" 
	}
}

IF ($CRvalues -ne '') {
	$CR = 'REPLACE INTO hpf_cashregister (PosiFlexDataID,CR_Number,CR_Config1,CR_DrawerFailedOpenCount,CR_ModelName,CR_PID,CR_Status,CR_RecordNumber,CR_ManufactureDate,EntryDate)'
	$CR = $CR + $CRvalues 
}

<#	This section will be run to extract MSR data from the XML. It
	runs through a for loop which pulls  is information from the XML for each of
	the MSR attributes. #>

For ($I=1;$I -Le 5; $I++){

	Try {
		$xpath = '/RMS_INFO/POS_USB_MSR'+$I+'_Part/USB_MSR1[5]/@HoursPowered'
		$MSR_HoursPoweredCount = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_MSR'+$I+'_Part/USB_MSR'+$I+'[1]/@ModelName'
		$MSR_ModelName = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_MSR'+$I+'_Part/USB_MSR'+$I+'[9]/@UnreadableCard'
		$MSR_UnreadableCard = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_MSR'+$I+'_Part/USB_MSR'+$I+'[8]/@FailedRead'
		$MSR_FailedRead = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}
	IF ($MSRvalues -eq '') {
		$MSRvalues = " VALUES(`'@PosiflexID@`',`'$I`',`'$MSR_HoursPoweredCount`',`'$MSR_FailedRead`',`'$MSR_ModelName`',`'$MSR_UnreadableCard`',`'@NewRecordNumber@`',`'$EntryDate`')" 
	}Else{
		$MSRvalues = $MSRvalues + ",(`'@PosiflexID@`',`'$I',`'$MSR_HoursPoweredCount`',`'$MSR_FailedRead`',`'$MSR_ModelName`',`'$MSR_UnreadableCard`',`'@NewRecordNumber@`',`'$EntryDate`')" 
	}
}

IF ($MSRvalues -ne '') {
	$MSR = 'REPLACE INTO hpf_stripereader (PosiFlexDataID,MSR_Number,MSR_HoursPoweredCount,MSR_FailedRead,MSR_ModelName,MSR_UnreadableCard,MSR_RecordNumber,EntryDate)'
	$MSR = $MSR + $MSRvalues 	
}


<#	This section will be run to extract Pole Display data from the XML. It
	runs through a for loop which pulls information from the XML for each of
	the Pole Display attributes. #>

For ($I=1;$I -Le 5; $I++){
	
	Try {
		$xpath = '/RMS_INFO/POS_USB_PD'+$I+'_Part/USB_PD'+$I+'[5]/@CommunicationErrorCount'
		$PDCommunicationErrorCount = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_PD'+$I+'_Part/USB_PD'+$I+'[1]/@ModelName'
		$PDModelName = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_USB_PD'+$I+'_Part/USB_PD'+$I+'[2]/@SerialNumber'
		$PDSerialNumber = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}
	IF ($PDvalues -eq '') {
		$PDvalues = " VALUES(`'@PosiflexID@`',`'$I`',`'$PDCommunicationErrorCount`',`'$PDModelName`',`'$PDSerialNumber`',`'@NewRecordNumber@`',`'$EntryDate`')" 
	}Else{
		$PDvalues = $PDvalues + ",(`'@PosiflexID@`',`'$I`',`'$PDCommunicationErrorCount`',`'$PDModelName`',`'$PDSerialNumber`',`'@NewRecordNumber@`',`'$EntryDate`')" 
	}
}
IF ($PDvalues -ne '') {
	$PD = 'REPLACE INTO  hpf_poledisplay (PosiFlexDataID,PD_Number,PD_CommunicationErrorCount,PD_ModelName,PD_SerialNumber,PD_RecordNumber,EntryDate)'
	$PD = $PD + $PDvalues 
}


<#	This section will be run to extract Printer data from the XML. It
	runs through a for loop which pulls information from the XML for each of
	the Pole Display attributes. #>

For ($I=1;$I -Le 5; $I++){
	Try {
		$xpath = '/RMS_INFO/POS_COM_PP'+$I+'_Part/COM_PP'+$I+'[5]/@InstallationDate'
		$PPInstallationDate = (Select-Xml -XPath $xpath -Xml $rms).ToString()

		$StartDate = [datetime]::ParseExact($PPInstallationDate,"yyyyMMdd",$null)
		$PP_PrinterAge = (New-TimeSpan -Start $StartDate -End $EndDate).Days
		
	}Catch {
		Break
	}
	
	Try {
		$xpath = '/RMS_INFO/POS_COM_PP'+$I+'_Part/COM_PP'+$I+'[12]/@FailedPaperCutCount'
		$PPFailedPaperCutCount = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}
	
	Try {
		$xpath = '/RMS_INFO/POS_COM_PP'+$I+'_Part/COM_PP'+$I+'[1]/@ModelName'
		$PPModelName = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}
	
	Try {
		$xpath = '/RMS_INFO/POS_COM_PP'+$I+'_Part/COM_PP'+$I+'[3]/@MechanicalRevision'
		$PPMechanicalRevision = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_COM_PP'+$I+'_Part/COM_PP'+$I+'[14]/@CharacterPrintedCount'
		$PPCharacterPrintedCount = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}

	Try {
		$xpath = '/RMS_INFO/POS_COM_PP'+$I+'_Part/POS/@COM_PP'+$I+'_CFG'
		$PPPOSConfig = (Select-Xml -XPath $xpath -Xml $rms).ToString()
	}Catch {
		Break
	}
	IF ($Printervalues -eq '') {
		$Printervalues = " VALUES(`'@PosiflexID@`',`'$I`',`'$PP_PrinterAge`',`'$PPCharacterPrintedCount`',`'$PPFailedPaperCutCount`',`'$PPMechanicalRevision`',`'$PPModelName`',`'$PPPOSConfig`',`'$PPInstallationDate`',`'@NewRecordNumber@`',`'$EntryDate`')" 
	}Else{
		$Printervalues = $Printervalues + ",(`'@PosiflexID@`',`'$I`',`'$PP_PrinterAge`',`'$PPCharacterPrintedCount`',`'$PPFailedPaperCutCount`',`'$PPMechanicalRevision`',`'$PPModelName`',`'$PPPOSConfig`',`'$PPInstallationDate`',`'@NewRecordNumber@`',`'$EntryDate`')" 
	}
}
IF ($Printervalues -ne '') {
	$Printer = 'REPLACE INTO hpf_receiptprinter(PosiFlexDataID,PP_Number,PP_PrinterAge,PP_CharacterPrintedCount,PP_FailedPaperCutCount,PP_MechanicalRevision,PP_ModelName,PP_POSConfig,PP_PrinterInstallDate,PP_RecordNumber,EntryDate)'
	$Printer = $Printer + $Printervalues 
}



<# 	This section will be run to extract is Epson Printer data from the XML. It
	runs through a for loop which pulls information from the XML for each of
	the Pole Display attributes. #>

Try {
	$xpath = '/RMS_INFO/Epson_USB_Part/POS/@Epson_PP'
	$EpsonPP = (Select-Xml -XPath $xpath -Xml $rms).ToString()

	$Epson = "REPLACE INTO hpf_epsonprinter (PosiFlexDataID,EpsonPP,EPP_RecordNumber,EntryDate)"
	$Epson = $Epson + " VALUES(`'@PosiflexID@`',`'$EpsonPP`',`'@NewRecordNumber@`',`'$EntryDate`')"
}Catch {
	$Epson = ''
}

<#	Return SQL statements to update Posiflex tables in LabTech database. #>

$Output = "EntryDate = $EntryDate"
IF ($CR -ne '') {$Output = "$Output | CashRegister = $CR"}
IF ($Epson -ne '') {$Output = "$Output | EpsonPrinter = $Epson"}
IF ($PD -ne '') {$Output = "$Output | PoleDisplay = $PD"}
IF ($Printer -ne '') {$Output = "$Output | Printer = $Printer"}
IF ($MSR -ne '') {$Output = "$Output | StripeReader = $MSR"}

$TestOutput = $CR + $Epson + $PD + $Printer + $MSR

IF ($TestOutput -eq '') {
	$Output = "Problem: Failed to read device data from XML file."
}

Write-Output $Output