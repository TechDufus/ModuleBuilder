function InitializeBuild {
    <#
        .SYNOPSIS
            Loads build.psd1 and the module manifest and combines them with the parameter values of the calling function. Pushes location to the module source location.
        .DESCRIPTION
            This function is for internal use from Build-Module only
            It does two things that make it really only work properly there:

            1. It calls Push-Location without Pop-Location to push the SourcePath into the "Build-Module" stack
            2. It reads the ParameterValues from the PARENT MyInvocation
        .NOTES
            Depends on the Configuration module Update-Object and (the built in Import-LocalizedData and Get-Module)
    #>
    [CmdletBinding()]
    param(
        # The root folder where the module source is (including the Build.psd1 and the module Manifest.psd1)
        [string]$SourcePath,

        # Pass the invocation from the parent in, so InitializeBuild can read parameter values
        [Parameter(DontShow)]
        $Invocation = $(Get-Variable MyInvocation -Scope 1 -ValueOnly)
    )
    Write-Debug "Initializing build variables"

    # NOTE: This reads the parameter values from Build-Module, passed in $Invocation!
    $BuildManifest = ResolveBuildManifest $SourcePath
    $BuildInfo = GetBuildInfo -Invocation $Invocation -BuildManifest $BuildManifest

    # These errors are caused by trying to parse valid module manifests without compiling the module first
    $ErrorsWeIgnore = "^" + @(
        "Modules_InvalidRequiredModulesinModuleManifest"
        "Modules_InvalidRootModuleInModuleManifest"
    ) -join "|^"


    # Finally, add all the information in the module manifest to the return object
    $ModuleInfo = Get-Module (Get-Item $BuildInfo.Path) -ListAvailable -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Problems

    # If there are any problems that count, fail
    if ($Problems = $Problems.Where({$_.FullyQualifiedErrorId -notmatch $ErrorsWeIgnore})) {
        foreach ($problem in $Problems) {
            Write-Error $problem
        }
        throw "Unresolvable problems in module manifest"
    }

    # Update the ModuleManifest with our build configuration
    $ModuleInfo = Update-Object -InputObject $ModuleInfo -UpdateObject $BuildInfo
    $ModuleInfo = Update-Object -InputObject $ModuleInfo -UpdateObject @{ DefaultCommandPrefix = $ModuleInfo.Prefix; Prefix = "" }

    # Ensure the OutputDirectory makes sense (it's never blank anymore)
    if (![IO.Path]::IsPathRooted($ModuleInfo.OutputDirectory)) {
        # Relative paths are relative to the build.psd1 now
        $OutputDirectory = Join-Path (Get-Location).Path $ModuleInfo.OutputDirectory
        $ModuleInfo.OutputDirectory = $OutputDirectory
    }

    $ModuleInfo
}