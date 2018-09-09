function Copy-DbaDbMail {
    <#
    .SYNOPSIS
        Migrates Mail Profiles, Accounts, Mail Servers and Mail Server Configs from one SQL Server to another.

    .DESCRIPTION
        By default, all mail configurations for Profiles, Accounts, Mail Servers and Configs are copied.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Type
        Specifies the object type to migrate. Valid options are "Job", "Alert" and "Operator". When Type is specified, all categories from the selected type will be migrated.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, existing objects on Destination with matching names from Source will be dropped.

    .NOTES
        Tags: Migration, Mail
        Author: Chrissy LeMaire (@cl), netnerds.net
        Requires: sysadmin access on SQL Servers

        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaDbMail

    .EXAMPLE
        Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster

        Copies all database mail objects from sqlserver2014a to sqlcluster using Windows credentials. If database mail objects with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster -SourceSqlCredential $cred

        Copies all database mail objects from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

    .EXAMPLE
        Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        Copy-DbaDbMail -Source sqlserver2014a -Destination sqlcluster -EnableException

        Performs execution of function, and will throw a terminating exception if something breaks
    #>
    [cmdletbinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [Parameter(ParameterSetName = 'SpecificTypes')]
        [ValidateSet('ConfigurationValues', 'Profiles', 'Accounts', 'mailServers')]
        [string[]]$Type,
        [PSCredential]$SourceSqlCredential,
        [PSCredential]$DestinationSqlCredential,
        [switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        function Copy-DbaDbMailConfig {
            [cmdletbinding(SupportsShouldProcess)]
            param ()

            Write-Message -Message "Migrating mail server configuration values." -Level Verbose
            $copyMailConfigStatus = [pscustomobject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = "Server Configuration"
                Type              = "Mail Configuration"
                Status            = $null
                Notes             = $null
                DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
            }
            if ($pscmdlet.ShouldProcess($destinstance, "Migrating all mail server configuration values.")) {
                try {
                    $sql = $mail.ConfigurationValues.Script() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                    Write-Message -Message $sql -Level Debug
                    $destServer.Query($sql) | Out-Null
                    $mail.ConfigurationValues.Refresh()
                    $copyMailConfigStatus.Status = "Successful"
                }
                catch {
                    $copyMailConfigStatus.Status = "Failed"
                    $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Unable to migrate mail configuration." -Category InvalidOperation -InnerErrorRecord $_ -Target $destServer
                }
                $copyMailConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }
        
        function Copy-DbaDatabaseAccount {
            [cmdletbinding(SupportsShouldProcess)]
            $sourceAccounts = $sourceServer.Mail.Accounts
            $destAccounts = $destServer.Mail.Accounts

            Write-Message -Message "Migrating accounts." -Level Verbose
            foreach ($account in $sourceAccounts) {
                $accountName = $account.name
                $copyMailAccountStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $accountName
                    Type              = "Mail Account"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($accounts.count -gt 0 -and $accounts -notcontains $accountName) {
                    continue
                }

                if ($destAccounts.name -contains $accountName) {
                    if ($force -eq $false) {
                        If ($pscmdlet.ShouldProcess($destinstance, "Account $accountName exists at destination. Use -Force to drop and migrate.")) {
                            $copyMailAccountStatus.Status = "Skipped"
                            $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Account $accountName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destinstance, "Dropping account $accountName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping account $accountName." -Level Verbose
                            $destServer.Mail.Accounts[$accountName].Drop()
                            $destServer.Mail.Accounts.Refresh()
                        }
                        catch {
                            $copyMailAccountStatus.Status = "Failed"
                            $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping account." -Target $accountName -Category InvalidOperation -InnerErrorRecord $_ -Continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destinstance, "Migrating account $accountName.")) {
                    try {
                        Write-Message -Message "Copying mail account $accountName." -Level Verbose
                        $sql = $account.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $copyMailAccountStatus.Status = "Successful"
                    }
                    catch {
                        $copyMailAccountStatus.Status = "Failed"
                        $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying mail account." -Target $accountName -Category InvalidOperation -InnerErrorRecord $_
                    }
                    $copyMailAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
        
        function Copy-DbaDbMailProfile {

            $sourceProfiles = $sourceServer.Mail.Profiles
            $destProfiles = $destServer.Mail.Profiles

            Write-Message -Message "Migrating mail profiles." -Level Verbose
            foreach ($profile in $sourceProfiles) {

                $profileName = $profile.name
                $copyMailProfileStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $profileName
                    Type              = "Mail Profile"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($profiles.count -gt 0 -and $profiles -notcontains $profileName) {
                    continue
                }

                if ($destProfiles.name -contains $profileName) {
                    if ($force -eq $false) {
                        If ($pscmdlet.ShouldProcess($destinstance, "Profile $profileName exists at destination. Use -Force to drop and migrate.")) {
                            $copyMailProfileStatus.Status = "Skipped"
                            $copyMailProfileStatus.Notes = "Already exists"
                            $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Profile $profileName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destinstance, "Dropping profile $profileName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping profile $profileName." -Level Verbose
                            $destServer.Mail.Profiles[$profileName].Drop()
                            $destServer.Mail.Profiles.Refresh()
                        }
                        catch {
                            $copyMailProfileStatus.Status = "Failed"
                            $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping profile." -Target $profileName -Category InvalidOperation -InnerErrorRecord $_ -Continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destinstance, "Migrating mail profile $profileName.")) {
                    try {
                        Write-Message -Message "Copying mail profile $profileName." -Level Verbose
                        $sql = $profile.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $destServer.Mail.Profiles.Refresh()
                        $copyMailProfileStatus.Status = "Successful"
                    }
                    catch {
                        $copyMailProfileStatus.Status = "Failed"
                        $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying mail profile." -Target $profileName -Category InvalidOperation -InnerErrorRecord $_
                    }
                    $copyMailProfileStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
        
        function Copy-DbaDbMailServer {
            [cmdletbinding(SupportsShouldProcess)]
            $sourceMailServers = $sourceServer.Mail.Accounts.MailServers
            $destMailServers = $destServer.Mail.Accounts.MailServers

            Write-Message -Message "Migrating mail servers." -Level Verbose
            foreach ($mailServer in $sourceMailServers) {
                $mailServerName = $mailServer.name
                $copyMailServerStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $mailServerName
                    Type              = "Mail Server"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }
                if ($mailServers.count -gt 0 -and $mailServers -notcontains $mailServerName) {
                    continue
                }

                if ($destMailServers.name -contains $mailServerName) {
                    if ($force -eq $false) {
                        if ($pscmdlet.ShouldProcess($destinstance, "Mail server $mailServerName exists at destination. Use -Force to drop and migrate.")) {
                            $copyMailServerStatus.Status = "Skipped"
                            $copyMailServerStatus.Notes = "Already exists"
                            $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Message "Mail server $mailServerName exists at destination. Use -Force to drop and migrate." -Level Verbose
                        }
                        continue
                    }

                    If ($pscmdlet.ShouldProcess($destinstance, "Dropping mail server $mailServerName and recreating.")) {
                        try {
                            Write-Message -Message "Dropping mail server $mailServerName." -Level Verbose
                            $destServer.Mail.Accounts.MailServers[$mailServerName].Drop()
                        }
                        catch {
                            $copyMailServerStatus.Status = "Failed"
                            $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Stop-Function -Message "Issue dropping mail server." -Target $mailServerName -Category InvalidOperation -InnerErrorRecord $_ -Continue
                        }
                    }
                }

                if ($pscmdlet.ShouldProcess($destinstance, "Migrating account mail server $mailServerName.")) {
                    try {
                        Write-Message -Message "Copying mail server $mailServerName." -Level Verbose
                        $sql = $mailServer.Script() | Out-String
                        $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                        Write-Message -Message $sql -Level Debug
                        $destServer.Query($sql) | Out-Null
                        $copyMailServerStatus.Status = "Successful"
                    }
                    catch {
                        $copyMailServerStatus.Status = "Failed"
                        $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Issue copying mail server" -Target $mailServerName -Category InvalidOperation -InnerErrorRecord $_
                    }
                    $copyMailServerStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
        
        try {
            Write-Message -Level Verbose -Message "Connecting to $Source"
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $mail = $sourceServer.mail
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $destinstance"
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            
            if ($type.Count -gt 0) {
                
                switch ($type) {
                    "ConfigurationValues" {
                        Copy-DbaDbMailConfig
                        $destServer.Mail.ConfigurationValues.Refresh()
                    }
                    
                    "Profiles" {
                        Copy-DbaDbMailProfile
                        $destServer.Mail.Profiles.Refresh()
                    }
                    
                    "Accounts" {
                        Copy-DbaDatabaseAccount
                        $destServer.Mail.Accounts.Refresh()
                    }
                    
                    "mailServers" {
                        Copy-DbaDbMailServer
                    }
                }
                
                continue
            }
            
            if (($profiles.count + $accounts.count + $mailServers.count) -gt 0) {
                
                if ($profiles.count -gt 0) {
                    Copy-DbaDbMailProfile -Profiles $profiles
                    $destServer.Mail.Profiles.Refresh()
                }
                
                if ($accounts.count -gt 0) {
                    Copy-DbaDatabaseAccount -Accounts $accounts
                    $destServer.Mail.Accounts.Refresh()
                }
                
                if ($mailServers.count -gt 0) {
                    Copy-DbaDbMailServer -mailServers $mailServers
                }
                
                continue
            }
            
            Copy-DbaDbMailConfig
            $destServer.Mail.ConfigurationValues.Refresh()
            Copy-DbaDatabaseAccount
            $destServer.Mail.Accounts.Refresh()
            Copy-DbaDbMailProfile
            $destServer.Mail.Profiles.Refresh()
            Copy-DbaDbMailServer
            $copyMailConfigStatus
            $copyMailAccountStatus
            $copyMailProfileStatus
            $copyMailServerStatus
            $enableDBMailStatus
            
        <# ToDo: Use Get/Set-DbaSpConfigure once the dynamic parameters are replaced. #>
            
            if (($sourceDbMailEnabled -eq 1) -and ($destDbMailEnabled -eq 0)) {
                if ($pscmdlet.ShouldProcess($destinstance, "Enabling Database Mail")) {
                    $sourceDbMailEnabled = ($sourceServer.Configuration.DatabaseMailEnabled).ConfigValue
                    Write-Message -Message "$sourceServer DBMail configuration value: $sourceDbMailEnabled." -Level Verbose
                    
                    $destDbMailEnabled = ($destServer.Configuration.DatabaseMailEnabled).ConfigValue
                    Write-Message -Message "$destServer DBMail configuration value: $destDbMailEnabled." -Level Verbose
                    $enableDBMailStatus = [pscustomobject]@{
                        SourceServer = $sourceServer.name
                        DestinationServer = $destServer.name
                        Name         = "Enabled on Destination"
                        Type         = "Mail Configuration"
                        Status       = if ($destDbMailEnabled -eq 1) { "Enabled" } else { $null }
                        DateTime     = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                    }
                    try {
                        Write-Message -Message "Enabling Database Mail on $destServer." -Level Verbose
                        $destServer.Configuration.DatabaseMailEnabled.ConfigValue = 1
                        $destServer.Alter()
                        $enableDBMailStatus.Status = "Successful"
                    }
                    catch {
                        $enableDBMailStatus.Status = "Failed"
                        $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Stop-Function -Message "Cannot enable Database Mail." -Category InvalidOperation -ErrorRecord $_ -Target $destServer
                    }
                    $enableDBMailStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlDatabaseMail
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-DbaDatabaseMail
    }
}