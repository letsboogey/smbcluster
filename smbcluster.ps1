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

#
#XenServer Powershell SnapIn functions
#

function add_XS_PSSnapin(){
     Write-Host "$($MyInvocation.MyCommand): Verifying XenServer PowerShell SnapIn..."
     #check if snapin is installed and registered
     if (Get-PSSnapin -registered | ?{$_.Name -eq "XenServerPSSnapIn"}){
        #load the snapin if it is not loaded
        if ((Get-PSSnapin -Name XenServerPSSnapIn -ErrorAction SilentlyContinue) -eq $null){
            Write-Host "$($MyInvocation.MyCommand): Loading XenServer PowerShell SnapIn..."
            Add-PSSnapin XenServerPSSnapIn
        }

        Write-Host "$($MyInvocation.MyCommand): XenServer PowerShell SnapIn successfully added"

     }else {
        Write-Host "$($MyInvocation.MyCommand): XenServerPSSnapIn not found, please install and register the snapin" `
                                                "Script exiting..."
        exit
     }
}

function remove_XS_PSSnapin(){
    Write-Host "$($MyInvocation.MyCommand): Removing XenServer PowerShell SnapIn and exiting script"
    Remove-PSSnapin XenServerPSSnapIn
    exit
}

#
#server connection functions
#

function connect_server([string]$svr, [string]$usr, [string]$pass){
    Write-Host "$($MyInvocation.MyCommand): Connecting to XenServer Host: $svr"
    $session = Connect-XenServer -Server $svr `
                                 -UserName $usr `
                                 -Password $pass `
                                 -NoWarnCertificates -SetDefaultSession -PassThru
    if($session){
        Write-Host "$($MyInvocation.MyCommand): Server connected"
        return $true
    }
    return $false 
}

function disconnect_server([string]$svr){
    Write-Host "$($MyInvocation.MyCommand): Disconnecting from XenServer Host: $svr"
    Get-XenSession -Server $svr | Disconnect-XenServer 

    if((Get-XenSession -Server $svr) -eq $null){
        Write-Host "$($MyInvocation.MyCommand): Server disconnected"
        return $false
    }
    return $true    
}

#
#VM functions
#

function create_VMs(){
    for($i=1 ; $i -le $NumNodes ;$i++){
        $vm_name = "WS12R2_node_"+ $i
        Invoke-XenVM -VM $template `
                     -XenAction Clone `
                     -NewName $VMname `
                     -Async -PassThru | Wait-XenTask -ShowProgress
        
        $vm = Get-XenVM | where{$_.name_label -eq $vm_name}
        $sr = Get-XenSR | where{$_.name_label -eq "Local storage"}
        
        $other_config = $vm.other_config
        
        $other_config["disks"] = $other_config["disks"].Replace('sr=""', 'sr="{0}"' -f $sr.uuid)

        #add cd drive and mount the windows iso
        New-XenVBD -VM $VM `
                   -VDI $winiso `
                   -Userdevice 1 `
                   -Bootable $true `
                   -Mode RO `
                   -Type CD `
                   -Unpluggable $true 
                   -Empty $false `
                   -OtherConfig @{} `
                   -QosAlgorithmType "" `
                   -QosAlgorithmParams @{}
        
        Set-XenVM -VM $VM -OtherConfig $other_config
  
        #provision vm 
        Invoke-XenVM -VM $VM -XenAction Provision -Async -PassThru | Wait-XenTask -ShowProgress   

        #boot vm and install windows server
        Invoke-XenVM -VM $VM -XenAction Start -Async -PassThru                   
    }
       
}

function delete_VMs(){
    
}

#
#BEGIN SCRIPT
#

#load snapin
add_XS_PSSnapin


try{
    #Connect to the server
    $connection = connect_server -svr $XenServerHost -usr $UserName -pass $Password

    #Use WS2012r2 template for VM's
    $template = Get-XenVM -Name "Windows Server 2012 R2 (64-bit)" | where{$_.is_a_template }

    #access XenRT Windows ISO SR
    $isolib = Get-XenSR | Where-Object{($_.name_label -eq 'XenRT Windows ISOs')}

    #get a specific windows iso
    $winiso = $isolib.VDIs | Get-XenVDI | Where-Object{$_.name_label -eq 'ws12r2u1-x64.iso'}
    Write-Host "$($MyInvocation.MyCommand): Server disconnected"

}catch{
    Write-Host $_.Exception.Message
} 



try{
    create_VMs
     

        

}catch{
        Write-Host "BUGGER!"
        Write-Host $_.Exception.Message
}finally{

    $connection = disconnect_server -svr $XenServerHost
    remove_XS_PSSnapin
}





