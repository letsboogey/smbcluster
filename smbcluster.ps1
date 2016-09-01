<#
    .SYNOPSIS
        Creates a Windows Server 2012R2 SMB3 failover cluster

    .DESCRIPTION
        This script automates the creation of a Windows Server 2012R2
        failover cluster and configures it to use SMB3 storage

    .PARAMETER XenServerHost
        The XenServer host to connect to

    .PARAMETER Nodes
        The VM nodes used to form the cluster

    .NOTES
        Copyright (c) Citrix Systems, Inc. All rights reserved.
        Version 1.0
#>

Param(
    [string]$XenServerHost = '10.71.71.150',
    [string]$UserName= '',
    [string]$Password = '',
    [int]$NumNodes = 3 

)

#loads the XenServer Powershell SnapIn
function loadPSSnapin(){
     Write-Host "$($MyInvocation.MyCommand): Verifying XenServer PowerShell SnapIn..."
     #check if snapin is installed and registered
     if (Get-PSSnapin -registered | ?{$_.Name -eq "XenServerPSSnapIn"}){
        #load the snapin if it is not loaded
        if ((Get-PSSnapin -Name XenServerPSSnapIn -ErrorAction SilentlyContinue) -eq $null){
            Write-Host "$($MyInvocation.MyCommand): Loading XenServer PowerShell SnapIn..."
            Add-PSSnapin XenServerPSSnapIn
             Write-Host "$($MyInvocation.MyCommand): XenServer PowerShell SnapIn successfully added"
        }
     }else {
        Write-Host "$($MyInvocation.MyCommand): XenServerPSSnapIn not found, please install and register the snapin" `
                                                "Script exiting..."
        exit
     }
}

#
#BEGIN SCRIPT
#
loadPSSnapin



try{
    #Connect to the server
    Write-Host "$($MyInvocation.MyCommand): Connecting to XenServer Host: $XenServerHost"
    $session = Connect-XenServer -Server $XenServerHost -UserName $UserName -Password $Password `
                -NoWarnCertificates -SetDefaultSession -PassThru

    Write-Host "$($MyInvocation.MyCommand): Building $NumNodes cluster nodes"
    #create desired number of VMs(cluster nodes) based on WS2012r2 template
    $template = Get-XenVM -Name "Windows Server 2012 R2 (64-bit)" | where{$_.is_a_template }

    #access XenRT Windows ISOs
    $isolib = Get-XenSR | Where-Object{($_.name_label -eq 'XenRT Windows ISOs')}

    #get a specific windows iso
    $distro = $isolib.VDIs | Get-XenVDI | Where-Object{$_.name_label -eq 'ws12r2u1-x64.iso'}
    Write-host "pass 1"
    for($i=1 ; $i -le $NumNodes ;$i++){
        $VMname = "WS12R2_node_"+ $i
        # $SRname = "node"+$i+"_vdi"
        write-host "pass 2"
        Invoke-XenVM -VM $template -XenAction Clone -NewName $VMname -Async `
                     -PassThru | Wait-XenTask -ShowProgress
        write-host "pass 3"
        $VM = Get-XenVM | where{$_.name_label -eq $VMname}
        $SR = Get-XenSR | where{$_.name_label -eq "Local storage"}
        write-host "pass 4"
        $other_config = $VM.other_config
        write-host "pass 5"
        $other_config["disks"] = $other_config["disks"].Replace('sr=""', 'sr="{0}"' -f $SR.uuid)
      
        write-host "pass 6"

        #add cd drive and mount the windows iso
        New-XenVBD -VM $VM -VDI $distro -Userdevice 1 -Bootable $true -Mode RO `
             -Type CD -Unpluggable $true -Empty $false -OtherConfig @{} `
             -QosAlgorithmType "" -QosAlgorithmParams @{}
        
        write-host "pass 8"
        Set-XenVM -VM $VM -OtherConfig $other_config
  
        #provision vm 
        Invoke-XenVM -VM $VM -XenAction Provision -Async -PassThru | Wait-XenTask -ShowProgress   
        
                 
    }
        

        

}catch{
        Write-Host "BUGGER!"
        Write-Host $_.Exception.Message
}finally{

    #Disconnect from server if there is an active connection
    if($session){
        Write-Host "$($MyInvocation.MyCommand): Disconnecting from XenServer Host: $XenServerHost"
        Disconnect-XenServer -Session $session
    }

    #Remove XenServerPSSnapin
    Write-Host "$($MyInvocation.MyCommand): Removing XenServer PowerShell SnapIn and exiting script"
    Remove-PSSnapin XenServerPSSnapIn
    exit
}





