<#
    .SYNOPSIS
        Creates a Windows Server 2012R2 SMB3 failover cluster

    .DESCRIPTION
        This script automates the creation of a Windows Server 2012R2
        failover cluster and configures it to use SMB3 storage

    .PARAMETER XenServerHost
        The XenServer host to connect to

    .PARAMETER NumNodes
        The number of VMs used to form the cluster

    .NOTES
        Copyright (c) Citrix Systems, Inc. All rights reserved.
        Version 1.0
#>

Param(
    [string]$XenServerHost = '10.71.71.150',
    [string]$UserName= 'poop',
    [string]$Password = 'pooppoop',
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

    #Use WS2012r2 template for VM's
    $template = Get-XenVM -Name "Windows Server 2012 R2 (64-bit)" | where{$_.is_a_template }

    #access XenRT Windows ISO SR
    Write-Host "$($MyInvocation.MyCommand): Getting windows iso from XenRT Windows ISOs SR"
    $isolib = Get-XenSR | Where-Object{($_.name_label -eq 'XenRT Windows ISOs')}

    #get a specific windows iso
    $winiso = $isolib.VDIs | Get-XenVDI | Where-Object{$_.name_label -eq 'ws12r2-x64.iso'}

    #add Ms to network 0 on host
    $network = Get-XenNetwork | where{$_.name_label.Contains("eth0")}

    for($i=1 ; $i -le $NumNodes ;$i++){
        $vm_name = "ws12r2_node"+ $i
        Invoke-XenVM -VM $template -XenAction Clone -NewName $vm_name `
                     -Async -PassThru | Wait-XenTask -ShowProgress
        
        $vm = Get-XenVM | where{$_.name_label -eq $vm_name}
        $sr = Get-XenSR | where{$_.name_label -eq "Local storage"}
        
        $other_config = $vm.other_config
        
        $other_config["disks"] = $other_config["disks"].Replace('sr=""', 'sr="{0}"' -f $sr.uuid)
        $other_config["is_cluster_node"] = "true"

        #add cd drive and mount the windows iso
        New-XenVBD -VM $vm -VDI $winiso -Userdevice 1 -Bootable $true -Mode RO `
                   -Type CD -Unpluggable $true -Empty $false -OtherConfig @{} `
                   -QosAlgorithmType "" -QosAlgorithmParams @{}

        Add-XenNetwork -Network $network 
        New-XenVIF -Network $network -Device 0 -VM $vm 
        
        
        Set-XenVM -VM $vm -OtherConfig $other_config
  
        #provision vm 
        Invoke-XenVM -VM $vm -XenAction Provision -Async -PassThru | Wait-XenTask -ShowProgress   

        #boot vm and install windows server
        Write-Host "$($MyInvocation.MyCommand): Starting VM: $vm_name"
        Invoke-XenVM -VM $vm -XenAction Start -Async -PassThru                   
    }
       
}

#function create_smb_sr([String]$sr_svr, [String]$sr_path, [String]$sr_name){
#
#try{
#      $sr_opq = New-XenSR -XenHost 10.71.128.31 -DeviceConfig @{ "server"=$sr_svr; "serverpath"=$sr_path; "options"=""} `
#                  -PhysicalSize 1024000000 -NameLabel $sr_name -NameDescription "testing smb create" -Type "smb" -ContentType "" `
#                  -Shared $true -SmConfig @{} -Async -PassThru `
#        | Wait-XenTask -ShowProgress 
#        }catch{
#                Write-host $_.Exception.Message
#        }
#}

function destroy_vm([XenAPI.VM]$vm){
    if ($vm -eq $null){
        return
    }

    $vdis = @()
    foreach($vbd in $vm.VBDs){
        if((Get-XenVBDProperty -Ref $vbd -XenProperty Mode) -eq [XenAPI.vbd_mode]::RW){
            $vdis += Get-XenVBDProperty -Ref $vbd -XenProperty VDI
        }
    }
  
    Remove-XenVM -VM $vm -Async -PassThru | Wait-XenTask -ShowProgress
    ForEach($vdi in $vdis){
        Remove-XenVDI -VDI $vdi -Async -PassThru | Wait-XenTask -ShowProgress
    }
}

function delete_VMs(){
    $vms = Get-XenVM | where{$_.domid -gt 0}
    if($vms){
        ForEach($vm in $vms){
            #shutdown and destroy VM and associated VDIs     
            Invoke-XenVM -VM $vm -XenAction HardShutdown -Async -Passthru | Wait-XenTask -ShowProgress
            destroy_vm($vm)
        }
    }
    return 
}

#
#BEGIN SCRIPT
#



try{

    #load snapin
    add_XS_PSSnapin

    #establish connection
    $connection = connect_server -svr $XenServerHost -usr $UserName -pass $Password
    
    #remove any existing VMs
    delete_VMs

    #create new VMs
    create_VMs

}catch{
        Write-Host "BUGGER!"
        Write-Host $_.Exception.Message
}finally{

    $connection = disconnect_server -svr $XenServerHost
    remove_XS_PSSnapin
}





