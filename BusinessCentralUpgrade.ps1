$ServerInstance = "MyServerInstance"
$DatabaseServer = "localhost"
$DatabaseName = "MyDatabase"

#microsoft apps
$dvdpath = "C:\Temp\BCDVD"
$bcversion = Get-ChildItem "C:\program files\Microsoft Dynamics 365 Business Central" | Select-Object -Last 1
$systemApp = "$dvdpath\ModernDev\program files\Microsoft Dynamics NAV\$bcversion\AL Development Environment\System.app"
$systemApplicationApp = "$dvdpath\Applications\system application\source\Microsoft_System Application.app"
$baseApplicationApp = "$dvdpath\Applications\BaseApp\Source\Microsoft_base Application.app"
$applicationApp = "$dvdpath\Applications\Application\Source\Microsoft_Application.app"                        
                        
#MS danish apps
$danishLanguageApp = "$dvdpath\Applications\BaseApp\Source\Microsoft_Danish language (Denmark).app"
$oiublApp = "$dvdpath\Applications\OIOUBL\Source\Microsoft_OIOUBL.app"
$paymentAndReconciliationFormatsDkApp = "$dvdpath\Applications\FIK\Source\Microsoft_Payment and Reconciliation Formats (DK).app"
$danishMsApps = @()
$danishMsApps += $danishLanguageApp
$danishMsApps += $oiublApp
$danishMsApps += $paymentAndReconciliationFormatsDkApp                   
                        
#PV apps
#get from folder - need to sort
$pvappsFolder = "C:\Temp\Upgrade\PrintVis apps"
                        
#PTE apps
#get from folder -need to sort
$pteappsFolder = "C:\Temp\Upgrade\PTE apps"                      
                        
# 3rd party apps
$continiaappsFolder = "C:\Temp\Upgrade\Continia apps"

#Prepare database
Measure-Command {
    Invoke-NAVApplicationDatabaseConversion -DatabaseServer $DatabaseServer -DatabaseName $DatabaseName -Force
    Start-NAVServerInstance $ServerInstance
    Sync-NAVTenant $ServerInstance -Tenant default -Mode Sync -Force   
            
    Write-Host "Uninstalling and unpublishing all apps" -ForegroundColor Yellow
    do { 
        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -ErrorAction SilentlyContinue 
        foreach ($app in $apps) {
            Uninstall-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version -Force -ErrorAction SilentlyContinue
            Unpublish-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version -ErrorAction SilentlyContinue
        }
    } while (($apps = (Get-NAVAppInfo -ServerInstance $ServerInstance | Measure-Object).Count) -gt 0)
    do {
        $symbols = Get-NAVAppInfo -ServerInstance $ServerInstance -SymbolsOnly
        foreach ($symbol in $symbols) {
            Uninstall-NAVApp -ServerInstance $ServerInstance -Name $symbol.Name -Version $symbol.Version -Force -ErrorAction SilentlyContinue
            Unpublish-NAVApp -ServerInstance $ServerInstance -Name $symbol.Name -Version $symbol.Version -ErrorAction SilentlyContinue
        }
    } while (($symbols = (Get-NAVAppInfo -ServerInstance $ServerInstance | Measure-Object).Count) -gt 0)
    
    Write-Host "Synchronizing the tenant" -ForegroundColor Yellow
    Sync-NAVTenant $ServerInstance -Tenant default -Mode Sync -Force 
    Test-NAVTenantDatabaseSchema -ServerInstance $ServerInstance
}

Measure-Command {
                        
    Write-Host "Publishing, synchronizing and installing BC symbols, system and base apps"
                        
    Publish-NAVApp -ServerInstance $ServerInstance -Path $systemApp -PackageType SymbolsOnly 
    Publish-NAVApp -ServerInstance $ServerInstance -Path $systemApplicationApp
    Sync-NAVTenant $ServerInstance -Force -Mode Sync 
    Sync-NAVApp $ServerInstance -Name "System Application"  -Force 
    Start-NAVAppDataUpgrade $ServerInstance -Name "System Application" -SkipVersionCheck -Force 
    Publish-NAVApp -ServerInstance $ServerInstance -Path $baseApplicationApp 
    Sync-NAVApp $ServerInstance -Name "Base Application" -Force 
    Start-NAVAppDataUpgrade $ServerInstance -Name "Base Application"  
    Publish-NAVApp $ServerInstance -Path $applicationApp 
    Sync-NAVApp $ServerInstance -Name "Application" -Force 
    Start-NAVAppDataUpgrade $ServerInstance -Name "Application" 
}

#Set NAV application version
$appVersion = ((Get-NAVAppInfo -ServerInstance $ServerInstance -Name "Application").Version).ToString()                           
Set-NAVApplication -ServerInstance $ServerInstance -ApplicationVersion $appVersion -Force 

    Sync-NavTenant $ServerInstance -Force -Mode Sync 
    Start-NAVDataUpgrade -FunctionExecutionMode Serial -ServerInstance $ServerInstance -force
                        
    $Stop = $false
    while (!$Stop) {
        $NAVDataUpgradeStatus = Get-NAVDataUpgrade -ServerInstance $ServerInstance 
        Write-Host "$($NAVDataUpgradeStatus.State) -- $($NAVDataUpgradeStatus.Progress)" -ForeGroundColor Gray
        if ($NAVDataUpgradeStatus.State -eq 'Suspended') {
            Resume-NAVDataUpgrade -ServerInstance $ServerInstance 
        }
        if (($NAVDataUpgradeStatus.State -eq 'Stopped') -or ($NAVDataUpgradeStatus.State -eq 'Completed')) {
            $Stop = $true
        }
        $ErrorsDataUpgrade = Get-NAVDataUpgrade -ServerInstance $ServerInstance -ErrorOnly
        if ($ErrorsDataUpgrade) {
            foreach ($ErrorDataUpgrade in $ErrorsDataUpgrade) {
                Write-Error "Error in function $($ErrorDataUpgrade.FunctionName) and Company $($ErrorDataUpgrade.CompanyName)`r`n $($ErrorDataUpgrade.Error)"
            }
            $Stop = $true
        }
        Start-Sleep 2
    }
    write-host "Data upgrade status: $($NAVDataUpgradeStatus.State)" -ForegroundColor Green        


#Install other MS DVD apps        
Write-Host "Publishing MS dk apps" -ForegroundColor Yellow
for ($i = 0; $i -lt 10; $i++) {
    Foreach ($app in $danishMsApps) {
        Publish-NAVApp -ServerInstance $ServerInstance -Path $app -ErrorAction SilentlyContinue
    }
}     
            
#Install PrintVis apps
$app = (Get-ChildItem $pvappsFolder -Filter "*Library*.app" -Recurse).FullName
Publish-NAVApp -ServerInstance $ServerInstance -Path $app
$name = $app -split "_" | Select-Object -Index 1
Sync-NAVApp -ServerInstance $ServerInstance -Name $name
$appFolder = $pvappsFolder
$apps = (Get-ChildItem -Path $appfolder -Filter "*.app" -Recurse).FullName

Write-Host "Publishing PrintVis app" -ForegroundColor Yellow
Foreach ($app in $apps) {
    if ($app -ilike "*PrintVis_*") {
        Publish-NAVApp -ServerInstance $ServerInstance -Path $app
        $name = $app -split "_" | Select-Object -Index 1
        Sync-NAVApp -ServerInstance $ServerInstance -Name $name
    }
}

Write-Host "Publishing other PrintVis apps" -ForegroundColor Yellow
Foreach ($app in $apps) {
    if ($app -inotlike "*PrintVis_*") {
        Publish-NAVApp -ServerInstance $ServerInstance -Path $app            
    }
}                         
            
#Install 3rd Party apps
$appfolder = $continiaappsFolder
$apps = (Get-ChildItem -Path $appfolder -Filter "*.app" -Recurse).FullName            
Write-Host "Publishing Continia apps" -ForegroundColor Yellow
for ($i = 0; $i -lt 10; $i++) {
    Foreach ($app in $apps) {
        Publish-NAVApp -ServerInstance $ServerInstance -Path $app -ErrorAction SilentlyContinue
    }        
}
            
#Install PTE apps
$appfolder = $pteappsFolder
$apps = (Get-ChildItem -Path $appfolder -Filter "*.app" -Recurse).FullName              
Write-Host "Publishing PTE apps" -ForegroundColor Yellow
for ($i = 0; $i -lt 10; $i++) {
    Foreach ($app in $apps) {
        Publish-NAVApp -ServerInstance $ServerInstance -Path $app -SkipVerification -ErrorAction SilentlyContinue
    }     
}

#Synchronize and Upgrade all apps
Write-Host "Synchronizing and Upgrading apps" -ForegroundColor Yellow           
for ($i = 0; $i -lt 10; $i++) {
    $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -ErrorAction SilentlyContinue 
    foreach ($app in $apps) {
        Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version 
        Install-NAVApp -ServerInstance $ServerInstance  -Name $app.Name -Version $app.Version -ErrorAction SilentlyContinue
        Start-NavAppDataUpgrade -ServerInstance $ServerInstance -Name $app.Name -Version $app.Version -Force -ErrorAction SilentlyContinue              
    }
}

$ServicesAddinsFolder = "C:\Program Files\Microsoft Dynamics 365 Business Central\$bcversion\Service\Add-ins"
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.BusinessChart' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'BusinessChart\Microsoft.Dynamics.Nav.Client.BusinessChart.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.FlowIntegration' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'FlowIntegration\Microsoft.Dynamics.Nav.Client.FlowIntegration.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.OAuthIntegration' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'OAuthIntegration\Microsoft.Dynamics.Nav.Client.OAuthIntegration.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.PageReady' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'PageReady\Microsoft.Dynamics.Nav.Client.PageReady.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.PowerBIManagement' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'PowerBIManagement\Microsoft.Dynamics.Nav.Client.PowerBIManagement.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.RoleCenterSelector' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'RoleCenterSelector\Microsoft.Dynamics.Nav.Client.RoleCenterSelector.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.SatisfactionSurvey' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'SatisfactionSurvey\Microsoft.Dynamics.Nav.Client.SatisfactionSurvey.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.SocialListening' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'SocialListening\Microsoft.Dynamics.Nav.Client.SocialListening.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.VideoPlayer' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'VideoPlayer\Microsoft.Dynamics.Nav.Client.VideoPlayer.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.WebPageViewer' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'WebPageViewer\Microsoft.Dynamics.Nav.Client.WebPageViewer.zip')
Set-NAVAddIn -ServerInstance $ServerInstance -AddinName 'Microsoft.Dynamics.Nav.Client.WelcomeWizard' -PublicKeyToken 31bf3856ad364e35 -ResourceFile ($AppName = Join-Path $ServicesAddinsFolder 'WelcomeWizard\Microsoft.Dynamics.Nav.Client.WelcomeWizard.zip')