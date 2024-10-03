###Requires racadm
###
Param ([bool]$install=$false,$csvFileName, $customIsoName)
$racadmCmd = "C:\Program Files\Dell\SysMgt\rac5\racadm.exe"
$iDracServers = Get-Content $csvFileName | ConvertFrom-Csv -Header $("IP","User","Pass")
If ($install){
    foreach ($idrac in $iDracServers) {
    
        write-host "Connecting to : $idrac.IP"
        &$racadmCmd -r $idrac.IP -u $idrac.User -p $idrac.Pass remoteimage -c -u vlcinstaller -p VMware123! -l $customIsoName
        write-host "Disabling BMC pass-thru"
        &$racadmCmd -r $idrac.IP -u $idrac.User -p $idrac.Pass set iDRAC.OS-BMC.AdminState Disabled
        write-host "Setting Boot Order to Virt CD : $idrac.IP"
        &$racadmCmd -r $idrac.IP -u $idrac.User -p $idrac.Pass set idrac.ServerBoot.FirstBootDevice VCD-DVD
        write-host "PowerCycling : $idrac.IP"
        &$racadmCmd -r $idrac.IP -u $idrac.User -p $idrac.Pass serveraction powercycle
    }
} else {
    foreach ($idrac in $iDracServers) {
        write-host "Disconnecting remote image from : $idrac.IP"
        &$racadmCmd -r $idrac.IP -u $idrac.User -p $idrac.Pass remoteimage -d
        &$racadmCmd -r $idrac.IP -u $idrac.User -p $idrac.Pass remoteimage -s
    }
}
