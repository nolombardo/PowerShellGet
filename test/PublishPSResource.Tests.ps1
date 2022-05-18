# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

Import-Module "$psscriptroot\PSGetTestUtils.psm1" -Force

Describe "Test Publish-PSResource" {
    BeforeAll {
        Get-NewPSResourceRepositoryFile

        # Register temporary repositories
        $tmpRepoPath = Join-Path -Path $TestDrive -ChildPath "tmpRepoPath"
        New-Item $tmpRepoPath -Itemtype directory -Force
        $testRepository = "testRepository"
        Register-PSResourceRepository -Name $testRepository -Uri $tmpRepoPath -Priority 1 -ErrorAction SilentlyContinue
        $script:repositoryPath = [IO.Path]::GetFullPath((get-psresourcerepository "testRepository").Uri.AbsolutePath)

        $tmpRepoPath2 = Join-Path -Path $TestDrive -ChildPath "tmpRepoPath2"
        New-Item $tmpRepoPath2 -Itemtype directory -Force
        $testRepository2 = "testRepository2"
        Register-PSResourceRepository -Name $testRepository2 -Uri $tmpRepoPath2 -ErrorAction SilentlyContinue
        $script:repositoryPath2 = [IO.Path]::GetFullPath((get-psresourcerepository "testRepository2").Uri.AbsolutePath)

        # Create module
        $script:tmpModulesPath = Join-Path -Path $TestDrive -ChildPath "tmpModulesPath"
        $script:PublishModuleName = "PSGetTestModule"
        $script:PublishModuleBase = Join-Path $script:tmpModulesPath -ChildPath $script:PublishModuleName
        if(!(Test-Path $script:PublishModuleBase))
        {
            New-Item -Path $script:PublishModuleBase -ItemType Directory -Force
        }

        #Create dependency module
        $script:DependencyModuleName = "PackageManagement"
        $script:DependencyModuleBase = Join-Path $script:tmpModulesPath -ChildPath $script:DependencyModuleName
        if(!(Test-Path $script:DependencyModuleBase))
        {
            New-Item -Path $script:DependencyModuleBase -ItemType Directory -Force
        }

        # Create temp destination path
        $script:destinationPath = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive -ChildPath "tmpDestinationPath"))
        New-Item $script:destinationPath -ItemType directory -Force
    }
    AfterAll {
    #    Get-RevertPSResourceRepositoryFile
    }
    AfterEach {
      # Delete all contents of the repository without deleting the repository directory itself
     # $pkgsToDelete = Join-Path -Path "$script:repositoryPath" -ChildPath "*"
     # Remove-Item $pkgsToDelete -Recurse

     # $pkgsToDelete = Join-Path -Path "$script:repositoryPath2" -ChildPath "*"
     # Remove-Item $pkgsToDelete -Recurse
    }

    It "Publish a module with -Path to the highest priority repo" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"

        Publish-PSResource -Path $script:PublishModuleBase

        $expectedPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        (Get-ChildItem $script:repositoryPath).FullName | Should -Be $expectedPath
    }

    It "Publish a module with -Path and -Repository" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"

        Publish-PSResource -Path $script:PublishModuleBase -Repository $testRepository2

        $expectedPath = Join-Path -Path $script:repositoryPath2  -ChildPath "$script:PublishModuleName.$version.nupkg"
        (Get-ChildItem $script:repositoryPath2).FullName | Should -Be $expectedPath
    }

    It "Publish a module with dependencies" {
        # Create dependency module
        $dependencyVersion = "2.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:DependencyModuleBase -ChildPath "$script:DependencyModuleName.psd1") -ModuleVersion $dependencyVersion -Description "$script:DependencyModuleName module"

        Publish-PSResource -Path $script:DependencyModuleBase

        # Create module to test
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module" -RequiredModules @(@{ModuleName = 'PackageManagement'; ModuleVersion = '2.0.0' })

        Publish-PSResource -Path $script:PublishModuleBase

        $nupkg = Get-ChildItem $script:repositoryPath | select-object -Last 1
        $nupkg.Name | Should Be "$script:PublishModuleName.$version.nupkg"
    }

    It "Publish a module with a dependency that is not published, should throw" {
        $version = "1.0.0"
        $dependencyVersion = "2.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module" -RequiredModules @(@{ModuleName = 'PackageManagement'; ModuleVersion = '1.4.4' })

        {Publish-PSResource -Path $script:PublishModuleBase -ErrorAction Stop} | Should -Throw -ErrorId "DependencyNotFound,Microsoft.PowerShell.PowerShellGet.Cmdlets.PublishPSResource"
    }


    It "Publish a module with -SkipDependenciesCheck" {
        $version = "1.0.0"
        $dependencyVersion = "2.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module" -RequiredModules @{ModuleName = "$script:DependencyModuleName"; ModuleVersion = "$dependencyVersion" }

        Publish-PSResource -Path $script:PublishModuleBase -SkipDependenciesCheck

        $expectedPath = Join-Path -Path $script:repositoryPath -ChildPath "$script:PublishModuleName.$version.nupkg"
        (Get-ChildItem $script:repositoryPath).FullName | select-object -Last 1 | Should -Be $expectedPath
    }
    
    <# The following tests are related to passing in parameters to customize a nuspec.
     # These parameters are not going in the current release, but is open for discussion to include in the future.
    It "Publish a module with -Nuspec" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"  -NestedModules "$script:PublishModuleName.psm1"

        # Create nuspec
        $nuspec =
@'
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2011/08/nuspec.xsd">
  <metadata>
    <id>PSGetTestModule</id>
    <version>1.0.0</version>
    <authors>americks</authors>
    <owners>americks</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>test</description>
    <releaseNotes></releaseNotes>
    <copyright>(c) 2021 Contoso Corporation. All rights reserved.</copyright>
    <tags>PSModule</tags>
  </metadata>
</package>
'@

        $nuspecPath = Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.nuspec"
        New-Item $nuspecPath -ItemType File -Value $nuspec

        Publish-PSResource -Path $script:PublishModuleBase -Nuspec $nuspecPath

        $expectedPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        Get-ChildItem $script:repositoryPath | Should -Be $expectedPath
    }

    It "Publish a module with -ReleaseNotes" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"  -NestedModules "$script:PublishModuleName.psm1"

        $releaseNotes = "Test release notes."
        Publish-PSResource -Path $script:PublishModuleBase -ReleaseNotes $releaseNotes

        $expectedNupkgPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        Get-ChildItem $script:repositoryPath | Should -Be $expectedNupkgPath

        $expectedExpandedPath = Join-Path -Path $script:repositoryPath -ChildPath "ExpandedPackage"
        New-Item -Path $expectedExpandedPath -ItemType directory
        Expand-Archive -Path $expectedNupkgPath -DestinationPath $expectedExpandedPath

        $expectedNuspec = Join-path -Path $expectedExpandedPath -ChildPath "$script:PublishModuleName.nuspec"
        $expectedNuspecContents =  Get-Content -Path $expectedNuspec -Raw
        $expectedNuspecContents.Contains($releaseNotes) | Should Be $true
    }

    It "Publish a module with -LicenseUrl" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"  -NestedModules "$script:PublishModuleName.psm1"

        $licenseUrl = "https://www.fakelicenseurl.com"
        Publish-PSResource -Path $script:PublishModuleBase -LicenseUrl $licenseUrl

        $expectedNupkgPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        Get-ChildItem $script:repositoryPath | Should -Be $expectedNupkgPath

        $expectedExpandedPath = Join-Path -Path $script:repositoryPath -ChildPath "ExpandedPackage"
        New-Item -Path $expectedExpandedPath -ItemType directory
        Expand-Archive -Path $expectedNupkgPath -DestinationPath $expectedExpandedPath

        $expectedNuspec = Join-path -Path $expectedExpandedPath -ChildPath "$script:PublishModuleName.nuspec"
        $expectedNuspecContents =  Get-Content -Path $expectedNuspec -Raw
        $expectedNuspecContents.Contains($licenseUrl) | Should Be $true
    }

    It "Publish a module with -IconUrl" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"  -NestedModules "$script:PublishModuleName.psm1"

        $iconUrl = "https://www.fakeiconurl.com"
        Publish-PSResource -Path $script:PublishModuleBase -IconUrl $iconUrl

        $expectedNupkgPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        Get-ChildItem $script:repositoryPath | Should -Be $expectedNupkgPath

        $expectedExpandedPath = Join-Path -Path $script:repositoryPath -ChildPath "ExpandedPackage"
        New-Item -Path $expectedExpandedPath -ItemType directory
        Expand-Archive -Path $expectedNupkgPath -DestinationPath $expectedExpandedPath

        $expectedNuspec = Join-path -Path $expectedExpandedPath -ChildPath "$script:PublishModuleName.nuspec"
        $expectedNuspecContents =  Get-Content -Path $expectedNuspec -Raw
        $expectedNuspecContents.Contains($iconUrl) | Should Be $true
    }


    It "Publish a module with -ProjectUrl" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"  -NestedModules "$script:PublishModuleName.psm1"

        $projectUrl = "https://www.fakeprojectUrl.com"
        Publish-PSResource -Path $script:PublishModuleBase -ProjectUrl $projectUrl

        $expectedNupkgPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        Get-ChildItem $script:repositoryPath | Should -Be $expectedNupkgPath

        $expectedExpandedPath = Join-Path -Path $script:repositoryPath -ChildPath "ExpandedPackage"
        New-Item -Path $expectedExpandedPath -ItemType directory
        Expand-Archive -Path $expectedNupkgPath -DestinationPath $expectedExpandedPath

        $expectedNuspec = Join-path -Path $expectedExpandedPath -ChildPath "$script:PublishModuleName.nuspec"
        $expectedNuspecContents =  Get-Content -Path $expectedNuspec -Raw
        $expectedNuspecContents.Contains($projectUrl) | Should Be $true
    }

    It "Publish a module with -Tags" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"  -NestedModules "$script:PublishModuleName.psm1"
        $tags = "Tag1"
        Publish-PSResource -Path $script:PublishModuleBase -Tags $tags

        $expectedNupkgPath = Join-Path -Path $script:repositoryPath  -ChildPath "$script:PublishModuleName.$version.nupkg"
        Get-ChildItem $script:repositoryPath | Should -Be $expectedNupkgPath

        $expectedExpandedPath = Join-Path -Path $script:repositoryPath -ChildPath "ExpandedPackage"
        New-Item -Path $expectedExpandedPath -ItemType directory
        Expand-Archive -Path $expectedNupkgPath -DestinationPath $expectedExpandedPath

        $expectedNuspec = Join-path -Path $expectedExpandedPath -ChildPath "$script:PublishModuleName.nuspec"
        $expectedNuspecContents =  Get-Content -Path $expectedNuspec -Raw
        $expectedNuspecContents.Contains($tags) | Should Be $true
    }
#>
    It "Publish a module to PSGallery without -APIKey, should throw" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"

        Publish-PSResource -Path $script:PublishModuleBase -Repository PSGallery -ErrorAction SilentlyContinue

        $Error[0].FullyQualifiedErrorId | Should -be "APIKeyError,Microsoft.PowerShell.PowerShellGet.Cmdlets.PublishPSResource"
    }

    It "Publish a module to PSGallery using incorrect API key, should throw" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"

        Publish-PSResource -Path $script:PublishModuleBase -Repository PSGallery -APIKey "123456789" -ErrorAction SilentlyContinue

        $Error[0].FullyQualifiedErrorId | Should -be "403Error,Microsoft.PowerShell.PowerShellGet.Cmdlets.PublishPSResource"
    }

    It "Publish a module with -Path -Repository and -DestinationPath" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"

        Publish-PSResource -Path $script:PublishModuleBase -Repository $testRepository2 -DestinationPath $script:destinationPath

        $expectedPath = Join-Path -Path $script:repositoryPath2 -ChildPath "$script:PublishModuleName.$version.nupkg"

        (Get-ChildItem $script:repositoryPath2).FullName | Should -Be $expectedPath

        $expectedPath = Join-Path -Path $script:destinationPath -ChildPath "$script:PublishModuleName.$version.nupkg"
        (Get-ChildItem $script:destinationPath).FullName | Should -Be $expectedPath
    }

    It "Publish a module and clean up properly when file in module is readonly" {
        $version = "1.0.0"
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $version -Description "$script:PublishModuleName module"

        # Create a readonly file that will throw access denied error if deletion is attempted
        $file = Join-Path -Path $script:PublishModuleBase -ChildPath "inaccessiblefile.txt"
        New-Item $file -Itemtype file -Force
        Set-ItemProperty -Path $file -Name IsReadOnly -Value $true

        Publish-PSResource -Path $script:PublishModuleBase -Repository $testRepository2

        $expectedPath = Join-Path -Path $script:repositoryPath2 -ChildPath "$script:PublishModuleName.$version.nupkg"
        (Get-ChildItem $script:repositoryPath2).FullName | Should -Be $expectedPath
    }

    <# The following tests required manual testing because New-ModuleManifest will not allow for incorrect syntax/formatting,
        At the moment, 'Update-ModuleManifest' is not yet complete, but that too should call 'Test-ModuleManifest', which also 
        does not allow for incorrect syntax. 
        It's still important to validate these scenarios because users may alter the module manifest manually, or the file may
        get corrupted. #>
    <#
    It "Publish a module with that has an invalid version format, should throw -- Requires Manual testing" {
        $incorrectVersion = '1..0.0'
        $correctVersion = '1.0.0.0'
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $incorrectVersion -Description "$script:PublishModuleName module" -RequiredModules @(@{ModuleName = 'PackageManagement'; ModuleVersion = $correctVersion })

        {Publish-PSResource -Path $script:PublishModuleBase -ErrorAction Stop} | Should -Throw -ErrorId "InvalidModuleManifest,Microsoft.PowerShell.PowerShellGet.Cmdlets.PublishPSResource"
    }

    It "Publish a module with a dependency that has an invalid version format, should throw -- Requires Manual testing" {
        $correctVersion = '1.0.0'
        $incorrectVersion = '1..0.0'
        New-ModuleManifest -Path (Join-Path -Path $script:PublishModuleBase -ChildPath "$script:PublishModuleName.psd1") -ModuleVersion $correctVersion -Description "$script:PublishModuleName module" -RequiredModules @(@{ModuleName = 'PackageManagement'; ModuleVersion = $incorrectVersion })

        {Publish-PSResource -Path $script:PublishModuleBase -ErrorAction Stop} | Should -Throw -ErrorId "InvalidModuleManifest,Microsoft.PowerShell.PowerShellGet.Cmdlets.PublishPSResource"
    }
    #>
}
