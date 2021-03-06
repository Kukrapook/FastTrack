<#       
    .DESCRIPTION
        Script to disable Audio and Video for All | Subset of Teams users

        The sample scripts are not supported under any Microsoft standard support 
        program or service. The sample scripts are provided AS IS without warranty  
        of any kind. Microsoft further disclaims all implied warranties including,  
        without limitation, any implied warranties of merchantability or of fitness for 
        a particular purpose. The entire risk arising out of the use or performance of  
        the sample scripts and documentation remains with you. In no event shall 
        Microsoft, its authors, or anyone else involved in the creation, production, or 
        delivery of the scripts be liable for any damages whatsoever (including, 
        without limitation, damages for loss of business profits, business interruption, 
        loss of business information, or other pecuniary loss) arising out of the use 
        of or inability to use the sample scripts or documentation, even if Microsoft 
        has been advised of the possibility of such damages.

        AUTHOR: Alejandro Lopez - alejanl@microsoft.com

        VERSION:
            v1.20180816

        REQUIREMENTS: 
            Skype for Business Online Module : https://www.microsoft.com/en-us/download/details.aspx?id=39366

	.PARAMETER ImportCSVFile
        This is optional. You can use this if you want to run the report against a subset of users. If empty, it'll run against all users in the tenant. 
        The CSV file needs to have "UserPrincipalName" as the column header. 
    .EXAMPLE
        .\Disable-TeamsAudioVideo.ps1 -ImportCSVFile "c:\userslist.csv"
        
#>
[Cmdletbinding()]
Param (
	[Parameter(mandatory=$true)][String]$ImportCSVFile
)

begin 
{
    #Functions
    Function Write-LogEntry {
        param(
            [string] $LogName ,
            [string] $LogEntryText,
            [string] $ForegroundColor
        )
        if ($LogName -NotLike $Null) {
            # log the date and time in the text file along with the data passed
            "$([DateTime]::Now.ToShortDateString()) $([DateTime]::Now.ToShortTimeString()) : $LogEntryText" | Out-File -FilePath $LogName -append;
            if ($ForeGroundColor -NotLike $null) {
                # for testing i pass the ForegroundColor parameter to act as a switch to also write to the shell console
                write-host $LogEntryText -ForegroundColor $ForeGroundColor
            }
        }
    }
    
    Try{
        $yyyyMMdd = Get-Date -Format 'yyyyMMdd'
        $computer = $env:COMPUTERNAME
        $user = $env:USERNAME
        $version = "1.20180816"
        $log = "$PSScriptRoot\Disable-TeamsAudioVideo-$yyyyMMdd.log"
        $policyDisabledVideo = "DisabledVideo"
        $policyDisabledAudio = "DisabledAudio"
        
        $disableAudio = $true
        $disableVideo = $true

        Write-LogEntry -LogName:$Log -LogEntryText "User: $user Computer: $computer Version: $version" -foregroundcolor Yellow

        try{$CSTenant = (Get-CsTenant).DisplayName}
        catch{}
        If ($CSTenant -ne $null){    
            Write-LogEntry -LogName:$Log -LogEntryText "Connected to Skype for Business Online" -ForegroundColor Green
        }
        Else {
            try{
                Import-Module SkypeOnlineConnector
                $sfbSession = New-CsOnlineSession 
                Import-PSSession $sfbSession | out-null    
            }
            catch{
                Write-LogEntry -LogName:$Log -LogEntryText "Unable to connect to Skype for Business Online: $_" -ForegroundColor Red
            }
        }

        $users = import-csv $ImportCSVFile -delimiter ","
        $NumOfUsers = $users.Count
        $csOnlineUsers = $users.UserPrincipalName | %{Get-CSOnlineUser -Identity $_}

    }
    catch{
        Write-LogEntry -LogName:$Log -LogEntryText "Pre-flight failed: $_" -foregroundcolor Red
    }
}

process 
{
    try{
        $i=0
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        $checkForDisabledVideoPolicy = Get-CsTeamsMeetingPolicy -PolicyName $policyDisabledVideo -erroraction silentlycontinue
        Foreach($user in $csOnlineUsers){
            If($disableVideo){
                Write-LogEntry -LogName:$Log -LogEntryText "Disabling Video for $($user.userprincipalname) ..." -foregroundcolor White
                $checkForExistingPolicy = $user.TeamsMeetingPolicy -ne $null
                If($checkForExistingPolicy){
                    Write-LogEntry -LogName:$Log -LogEntryText "Found existing policy: $($user.TeamsMeetingPolicy). Copying policy, disabling video, and applying..." 
                    $existingMeetingPolicy = Get-CsTeamsMeetingPolicy -Identity $user.TeamsMeetingPolicy
                    $newMeetingPolicy = $existingMeetingPolicy
                    $newMeetingPolicy.Identity = $existingMeetingPolicy.Identity.tostring() + "VIDEOOFF"
                    $newMeetingPolicy.AllowIPVideo = $false
                    #Get parameters: $newMeetingPolicy.psobject.properties.name | %{$parameters.add($_,$newMeetingPolicy.$_)}
                    $meetingPolicyProperties = "Identity","Description","AllowChannelMeetingScheduling","AllowMeetNow","AllowIPVideo","AllowAnonymousUsersToDialOut","AllowAnonymousUsersToStartMeeting","AllowPrivateMeetingScheduling","AutoAdmittedUsers","AllowCloudRecording","AllowOutlookAddIn","AllowPowerPointSharing","AllowParticipantGiveRequestControl","AllowExternalParticipantGiveRequestControl","AllowSharedNotes","AllowWhiteboard","AllowTranscription","MediaBitRateKb","ScreenSharingMode"
                    $meetingPolicyPropertyValues = @{}
                    $meetingPolicyProperties | %{$meetingPolicyPropertyValues.add($_,$newMeetingPolicy.$_)}
                    New-CsTeamsMeetingPolicy @meetingPolicyPropertyValues
                    Sleep 3 #allow some time for new policy to propagate
                    Grant-CsTeamsMeetingPolicy -PolicyName $newMeetingPolicy.Identity -identity $user.userprincipalname
                }
                Else{
                    Write-LogEntry -LogName:$Log -LogEntryText "No existing meeting policy found for user" 
                    If(!$checkForDisabledVideoPolicy){
                        Write-LogEntry -LogName:$Log -LogEntryText "Creating new meeting policy with video disabled..." 
                        New-CsTeamsMeetingPolicy -Identity $policyDisabledVideo -AllowIPVideo $false | out-null
                    }
                    Write-LogEntry -LogName:$Log -LogEntryText "Applying $policyDisabledVideo policy to user" 
                    Grant-CsTeamsMeetingPolicy -PolicyName $policyDisabledVideo -identity $user.userprincipalname
                }
            }
            If($disableAudio){
                Write-LogEntry -LogName:$Log -LogEntryText "Disabling Audio for $($user.userprincipalname) ..." -foregroundcolor White
                Grant-CsTeamsCallingPolicy -PolicyName "DisallowCalling" -Identity $user.userprincipalname
            }
            
            $i++
            if ($sw.Elapsed.TotalMilliseconds -ge 500) {
                Write-Progress -Activity "Disable Audio and Video" -Status "Done $i out of $NumOfUsers"
                $sw.Reset(); $sw.Start()
            }
        }
    }
    catch{
        Write-LogEntry -LogName:$Log -LogEntryText "Error with: $_" -foregroundcolor Red
    }
    	
}

End
{
    Write-LogEntry -LogName:$Log -LogEntryText "Total Elapsed Time: $($elapsed.Elapsed.ToString()). " -foregroundcolor White
    Write-LogEntry -LogName:$Log -LogEntryText "Total Users Processed: $NumOfUsers. " -foregroundcolor White
    Write-LogEntry -LogName:$Log -LogEntryText "Average Time Per User: $($elapsed.Elapsed.Seconds / $NumOfUsers)s." -foregroundcolor White
    Write-LogEntry -LogName:$Log -LogEntryText "Log: $log" -foregroundcolor Green
    try{Remove-PSSession $sfbSession -ErrorAction SilentlyContinue}catch{}
    ""
} 
 
