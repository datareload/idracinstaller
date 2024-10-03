###Req mkisofs.exe
###Creates an ISO with kickstart script to install ESXi passing in json of hosts
<#
{   
 "genVM": [
      {
        "name": "esxi-1",
		"mgmtip": "10.10.10.101",
		"subnetmask":"255.255.255.0",
		"ipgw":"10.10.10.253",
		"MacAddr":"78:AC:44:B0:34:48"
    }
  ]
}
#>      
param (
    [string]$addhostsjson,
    [String]$vSphereISOPath,
    $hostDomainName,
    $dnsServer,
    $ntpServer,
    $masterPassword,
    $vlanID
)
$global:scriptDir = $PSScriptRoot 
$global:dateFormat = "yyyyMMdd_HHmmss"
$logPathDir = New-Item -ItemType Directory -Path "$scriptDir\Logs" -Force
$logfile = "$logPathDir\VLC-Log-$(get-date -format $global:dateFormat).txt"
$tempDir = "Temp-$(Get-Date -Format $global:dateFormat)"
$isWindows = $true

Function logger($strMessage, [switch]$logOnly,[switch]$consoleOnly)
{
	$curDateTime = get-date -format "hh:mm:ss"
	$entry = "$curDateTime :> $strMessage"
    if ($consoleOnly) {
		write-host $entry
    } elseif ($logOnly) {
		$entry | out-file -Filepath $logfile -append
	} else {
        write-host $entry
		$entry | out-file -Filepath $logfile -append
	}
}
Function byteWriter($dataIn, $fileOut) 
{
	$bytedataIn = [System.Text.Encoding]::UTF8.GetBytes($dataIn)
	#Set-Content -Value $bytedataIn -Path $scriptDir\$tempDir\$fileout -AsByteStream
	[Byte[]] $byteDataIn = [System.Text.Encoding]::UTF8.GetBytes($dataIn)
    $defaultHostPath = "$scriptDir\$tempDir\$fileout"
    [System.IO.File]::WriteAllBytes($defaultHostPath,$byteDataIn) 
}
function extractvSphereISO ($vSphereISOPath)
{
   
   $folder = New-Item -Path $scriptDir/$tempDir -ItemType "directory" -Name ISO -Force
   if($isWindows){ 
    $mount = Mount-DiskImage -ImagePath "$vSphereISOPath" -PassThru
 
         if($mount) {
        
             $i=1
             do {
                $i++
                $volume = Get-DiskImage -ImagePath $mount.ImagePath | Get-Volume
                Start-Sleep 5
                $source = "$($volume.DriveLetter):\*"
             } until($i -gt 10 -Or $source)
             if (! $source) {
                 logger "ERROR: Could not get root mount for $vSphereISOPath"
                 Dismount-DiskImage -ImagePath "$vSphereISOPath"
                 exit
             }
        
             logger "Extracting '$vsphereISOPath' mounted on '$source' to '$folder'..."
            
             $params = @{Path = $source; Destination = $folder; Recurse = $true; Force = $true;}
             Copy-Item @params
             $hide = Dismount-DiskImage -ImagePath "$vSphereISOPath"
             logger "Copy complete"
        }
        else {
             logger "ERROR: Could not mount $vSphereISOPath check if file is already in use"
             exit
        }
   } else {
    	New-Item -Path /mnt -ItemType "directory" -Name iso -Force
	mount -o loop $vSphereISOPath /mnt/iso
	$source = "/mnt/iso/*"
        $params = @{Path = $source; Destination = $folder; Recurse = $true; Force = $true;}
        Copy-Item @params
	umount /mnt/iso
	#Remove-Item -Path "/mnt/iso" -Force

   }
}

extractvSphereISO($vsphereISOPath)

Set-ItemProperty $scriptDir\$tempDir\ISO\isolinux.bin -name IsReadOnly -value $false
Set-ItemProperty $scriptDir\$tempDir\ISO\isolinux.cfg -name IsReadOnly -value $false
Set-ItemProperty $scriptDir\$tempDir\ISO\boot.cfg -name IsReadOnly -value $false
Set-ItemProperty $scriptDir\$tempDir\ISO\efi\boot\boot.cfg -name IsReadOnly -value $false


$hostsToBuild = New-Object System.Collections.Arraylist
    $genvms = Get-Content -raw $addHostsJson | ConvertFrom-Json
    $genvms.genVM | ForEach-Object -Process {$hostsToBuild.Add($_)} 

$caseStatement = "case `$MAC_ADDR in`n"

foreach ($hostVM in $hostsToBuild) {

	$hostVMName = "$($userOptions.nestedVMPrefix)$($hostVM.name)"
    $hostFQDN = "$($hostVM.Name).$hostDomainName"
    $hostMgmtIP = $hostVM.mgmtip
    $hostSubnet = $hostVM.subnetmask
    $hostGW = $hostVM.ipgw
	$hostMacAddress = $($hostVM.MacAddr).ToLower()
        
    $caseStatement+="`t$hostMacAddress)`n"
    $caseStatement+="`t`tIPADDR=`"${hostMgmtIP}`"`n"
    $caseStatement+="`t`tIPGW=`"${hostGW}`"`n"
    $caseStatement+="`t`tSUBNET=`"${hostSubnet}`"`n"
    $caseStatement+="`t`tVM_NAME=`"${hostFQDN}`"`n"
    $caseStatement+="`t`tDNS=`"${dnsServer}`"`n"
    $caseStatement+="`t;;`n"

}

$caseStatement+="esac`n"

# Create Custom vSphere ISO

if ( -not (Test-Path ($scriptDir + "\$tempDir\ISO"))) {
    mkdir -Path "$scriptDir\$tempDir\ISO" -Force

}

logger "Setting ISOLINUX.CFG info... "

$isoLinuxCFG="DEFAULT MBOOT.C32`n"
$isoLinuxCFG+="  APPEND -c BOOT.CFG`n"

byteWriter $isoLinuxCFG "ISO\isolinux.cfg"

logger "Setting BOOT.CFG info...                "

$curBootCFG = Get-Content "$scriptDir\$tempDir\ISO\boot.cfg"
$curEFIBootCFG = Get-Content "$scriptDir\$tempDir\ISO\efi\boot\boot.cfg"
$bootCFGCount = 0 
foreach ($bootCfgLine in $curBootCFG) {

    if ($bootCfgLine.Contains("kernelopt")) {

        $curBootCFG[$bootCFGCount] = $curBootCFG[$bootCFGCount] + " ks=cdrom:/VLC.CFG"
        }
        $bootCFGCount++

}
$bootCFGCount = 0 
foreach ($bootCfgLine in $curEFIBootCFG) {

    if ($bootCfgLine.Contains("kernelopt")) {

        $curEFIBootCFG[$bootCFGCount] = $curEFIBootCFG[$bootCFGCount] + " ks=cdrom:/VLC.CFG"
        }
        $bootCFGCount++

}

$curBootCFG | Set-Content "$scriptDir\$tempDir\ISO\boot.cfg"
$curEFIBootCFG | Set-Content "$scriptDir\$tempDir\ISO\efi\boot\boot.cfg"
			
logger "Setting VLC.cfg info...                "
	
$kscfg="#VCF Scripted Nested Host Install`n"
$kscfg+="vmaccepteula`n"
$kscfg+="rootpw $masterPassword`n"
$kscfg+="clearpart --alldrives --overwritevmfs`n"
$kscfg+="install --firstdisk=DELL --overwritevmfs`n"
$kscfg+="reboot`n"
$kscfg+="`n"
$kscfg+="%include /tmp/hostConfig`n"
$kscfg+="`n"
$kscfg+="%pre --interpreter=busybox`n"
$kscfg+="MAC_ADDR=`$(localcli network nic list | awk '/vmnic0/' |  awk '{print `$8}')`n"
$kscfg+="echo `"Found MAC: `${MAC_ADDR}`" > /tmp/found.mac`n"
$kscfg+="${caseStatement}`n"
$kscfg+="echo `"network --bootproto=static --addvmportgroup=true --device=vmnic5 --ip=`${IPADDR} --netmask=`${SUBNET} --gateway=`${IPGW} --nameserver=`${DNS} --hostname=`${VM_NAME}`" > /tmp/hostConfig`n"
$kscfg+="%firstboot --interpreter=busybox`n"
$kscfg+="# SSH and ESXi shell`n"
$kscfg+="vim-cmd hostsvc/enable_ssh`n"
$kscfg+="vim-cmd hostsvc/start_ssh`n"
$kscfg+="# Add Network Portgroup`n"
if($($userOptions.mgmtNetVlan) -eq 0) {
    $kscfg+="esxcli network vswitch standard portgroup add --portgroup-name `"VM Network`" --vswitch-name vSwitch0`n"
} else {
    $kscfg+="esxcli network vswitch standard portgroup add --portgroup-name `"VM Network`" --vswitch-name vSwitch0`n"
    $kscfg+="esxcli network vswitch standard portgroup set --vlan-id=$($vlanID) --portgroup-name `"VM Network`"`n"
    $kscfg+="esxcli network vswitch standard portgroup set --vlan-id=$($vlanID) --portgroup-name `"Management Network`"`n"
}
$kscfg+="esxcli network vswitch standard set -v vSwitch0 -m 1500`n"
$kscfg+="esxcli network ip interface ipv4 address list >> /var/log/nicIP.txt`n"
$kscfg+="GETINT=`$(esxcli network ip interface ipv4 address list | grep vmk0)`n"
$kscfg+="IPADDR=`$(echo `"`${GETINT}`" | awk '{print `$2}')`n"
$kscfg+="SUBNET=`$(echo `"`${GETINT}`" | awk '{print `$3}')`n"
$kscfg+="IPGW=`$(echo `"`${GETINT}`" | awk '{print `$6}')`n"
$kscfg+="esxcfg-vmknic --del --portgroup `"Management Network`"`n"
$kscfg+="esxcfg-vmknic --add --portgroup `"Management Network`" --ip `${IPADDR} --netmask `${SUBNET} --mtu 1500`n"
$kscfg+="esxcfg-route -a default `${IPGW}`n"
#$kscfg+="esxcli system hostname set --fqdn=`$(echo hostname)`n"
$kscfg+="# Setup VSAN`n"
$kscfg+="esxcli system settings advanced set -o /VMFS3/HardwareAcceleratedLocking -i 1`n" 
$kscfg+="esxcli system settings advanced set -o /LSOM/VSANDeviceMonitoring -i 0`n"
$kscfg+="esxcli system settings advanced set -o /LSOM/lsomSlowDeviceUnmount -i 0`n"
$kscfg+="esxcli system settings advanced set -o /VSAN/SwapThickProvisionDisabled -i 1`n"
$kscfg+="esxcli system settings advanced set -o /VSAN/FakeSCSIReservations -i 1`n"
$kscfg+="esxcli vsan storage automode set --enabled=false`n"
$kscfg+="vdq -q >> /var/log/vlccheck.txt`n"
$kscfg+="vim-cmd hostsvc/datastore/destroy datastore1`n"
$kscfg+="esxcli network firewall ruleset set --ruleset-id=ntpClient -e true`n"
$kscfg+="esxcli system ntp set -e yes -s $ntpServer`n"
$kscfg+="esxcli system ntp config get >> /var/log/vlccheck.txt`n"
$kscfg+="esxcfg-advcfg -s 0 /Net/FollowHardwareMac`n"
$kscfg+="/sbin/chkconfig ntpd on`n"
$kscfg+="(`n"
$kscfg+="echo `"`"`n"
$kscfg+="echo export PS1=\`"\\033[01\;32m[\`${LOGNAME}@\\h:\\033[01\;34m\\w\\033[01\;32m]\\033[00m \`"`n"
$kscfg+=")>> /etc/profile.local`n"
$kscfg+="reboot -d 1`n"

byteWriter $kscfg "ISO\VLC.CFG"

if ($isWindows){
	$isoExe = "$scriptDir\bin\mkisofs.exe"
} else {
	$isoExe = "/usr/bin/genisoimage"
}

$scriptDirUnix = $scriptDir.Replace("\","/")
$currIso = "$(get-date -Format $global:dateFormat)-VLC_vsphere.iso"
if($isWindows){
    $isoExeArg = "-iso-level 4 -relaxed-filenames -J -b ISOLINUX.BIN -no-emul-boot -boot-load-size 8 -hide boot.catalog -eltorito-alt-boot -b EFIBOOT.IMG -no-emul-boot -ldots -o '$scriptDir/$tempDir/$currIso' '$scriptDirUnix/$tempDir/ISO'"
} else {
    $isoExeArg = "-iso-level 4 -relaxed-filenames -J -b isolinux.bin -no-emul-boot -boot-load-size 8 -hide boot.catalog -eltorito-alt-boot -b efiboot.img -no-emul-boot -ldots -o '$scriptDir/$tempDir/$currIso' '$scriptDirUnix/$tempDir/ISO'"   <# Action when all if and elseif conditions are false #>
}
Invoke-Expression -command "& '$isoExe' $isoExeArg" | out-null
