﻿[Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"] = @{ }

$ScriptBlock = {
    param (
        $commandName,
        
        $parameterName,
        
        $wordToComplete,
        
        $commandAst,
        
        $fakeBoundParameter
    )
    
    $start = Get-Date
    [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastExecution = $start
    
    $server = $fakeBoundParameter['SqlInstance']
    if (-not $server) { return }
    
    try
    {
        [DbaInstanceParameter]$parServer = $server | Select-Object -First 1
    }
    catch
    {
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
    
    if ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$parServer.FullSmoName.ToLower()])
    {
        foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
    
    try
    {
        $serverObject = Connect-SqlServer -SqlServer $parServer -SqlCredential $fakeBoundParameter['SqlCredential'] -ErrorAction Stop
        foreach ($name in ([Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Cache["database"][$parServer.FullSmoName.ToLower()] | Where-DbaObject -Like "$wordToComplete*"))
        {
            New-DbaTeppCompletionResult -CompletionText $name -ToolTip $name
        }
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
    catch
    {
        [Sqlcollective.Dbatools.TabExpansion.TabExpansionHost]::Scripts["database"].LastDuration = (Get-Date) - $start
        return
    }
}

Register-DbaTeppScriptblock -ScriptBlock $ScriptBlock -Name Database

$commands = "Get-DbaBackupHistory", "Get-DbaDatabase", "Backup-DbaDatabase", "Copy-DbaDatabase", "Expand-DbaTLogResponsibly", "Test-DbaVirtualLogFile", "Test-DbaMigrationConstraint", "Test-DbaLastBackup", "Test-DbaIdentityUsage", "Test-DbaFullRecoveryModel", "Test-DbaDatabaseOwner"

if ($TEPP) {
	TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $commands -ParameterName Database -ScriptBlock $ScriptBlock
	TabExpansionPlusPlus\Register-ArgumentCompleter -CommandName $commands -ParameterName Exclude -ScriptBlock $ScriptBlock
}
else {
	Register-ArgumentCompleter -CommandName $commands -ParameterName Database -ScriptBlock $ScriptBlock
	Register-ArgumentCompleter -CommandName $commands -ParameterName Exclude -ScriptBlock $ScriptBlock
}