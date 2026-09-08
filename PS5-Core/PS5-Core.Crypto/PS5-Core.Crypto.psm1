<#
.SYNOPSIS
    Cryptographic utilities for Windows PowerShell 5.1.

.DESCRIPTION
    File and string hashing with support for SHA256, SHA1 and MD5.

    File hashing goes through the Get-FileHash cmdlet rather than a raw
    SHA256/SHA1/MD5 .NET stream: the cmdlet ships with PowerShell 4.0+, it
    removes the stream lifetime handling entirely, and it is the form most
    likely to survive a locked-down host, where direct .NET method calls are
    refused. String hashing has no cmdlet equivalent and still uses .NET.

.NOTES
    Author:  Neuraaak
    License: MIT
#>

#region Public Functions

<#
.SYNOPSIS
    Calculates the cryptographic hash of a file.

.DESCRIPTION
    Returns the hash as a lowercase hexadecimal string without separators,
    or $null when the file cannot be hashed.

.PARAMETER Path
    The path to the file to hash. Resolved LITERALLY: a name containing
    brackets ('copie[1].txt', the canonical form of a downloaded duplicate) is
    a valid name, not a wildcard pattern.

.PARAMETER Algorithm
    SHA256 (default), SHA1 or MD5.

.PARAMETER UpperCase
    Return the hash in uppercase instead of lowercase.

.EXAMPLE
    Get-FileHashExtended -Path "C:\file.txt"

.OUTPUTS
    String containing the hash value, or $null on error.
#>
function Get-FileHashExtended {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [Alias('FilePath', 'FullName')]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256',

        [Parameter(Mandatory = $false)]
        [switch]$UpperCase
    )

    process {
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                Write-Error "File not found: $Path"
                return $null
            }

            $hash = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm -ErrorAction Stop).Hash

            if ($UpperCase) {
                return $hash.ToUpper()
            }
            return $hash.ToLower()
        }
        catch {
            Write-Error "Failed to compute hash for $Path : $_"
            return $null
        }
    }
}


<#
.SYNOPSIS
    Calculates the cryptographic hash of a string.

.PARAMETER String
    The string to hash.

.PARAMETER Algorithm
    SHA256 (default), SHA1 or MD5.

.PARAMETER Encoding
    The text encoding used to turn the string into bytes. Default: UTF8.

.PARAMETER UpperCase
    Return the hash in uppercase instead of lowercase.

.EXAMPLE
    Get-StringHash -String "Hello World"

.OUTPUTS
    String containing the hash value, or $null on error.
#>
function Get-StringHash {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipeline = $true
        )]
        [AllowEmptyString()]
        [string]$String,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256',

        [Parameter(Mandatory = $false)]
        [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF32')]
        [string]$Encoding = 'UTF8',

        [Parameter(Mandatory = $false)]
        [switch]$UpperCase
    )

    process {
        $hashObject = $null

        try {
            $hashObject = switch ($Algorithm) {
                'SHA256' { [System.Security.Cryptography.SHA256]::Create() }
                'SHA1' { [System.Security.Cryptography.SHA1]::Create() }
                'MD5' { [System.Security.Cryptography.MD5]::Create() }
            }

            $encoder = switch ($Encoding) {
                'UTF8' { [System.Text.Encoding]::UTF8 }
                'ASCII' { [System.Text.Encoding]::ASCII }
                'Unicode' { [System.Text.Encoding]::Unicode }
                'UTF32' { [System.Text.Encoding]::UTF32 }
            }

            $hashBytes = $hashObject.ComputeHash($encoder.GetBytes($String))
            $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''

            if ($UpperCase) {
                return $hashString
            }
            return $hashString.ToLower()
        }
        catch {
            Write-Error "Failed to compute hash for string: $_"
            return $null
        }
        finally {
            if ($hashObject) { $hashObject.Dispose() }
        }
    }
}


<#
.SYNOPSIS
    Verifies file integrity against a known hash.

.PARAMETER Path
    The path to the file to verify.

.PARAMETER ExpectedHash
    The expected hash value to compare against, in either case.

.PARAMETER Algorithm
    SHA256 (default), SHA1 or MD5.

.EXAMPLE
    Test-FileIntegrity -Path "C:\file.txt" -ExpectedHash "abc123..."

.OUTPUTS
    Boolean indicating whether the file hash matches the expected hash.
#>
function Test-FileIntegrity {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$ExpectedHash,

        [Parameter(Mandatory = $false)]
        [ValidateSet('SHA256', 'SHA1', 'MD5')]
        [string]$Algorithm = 'SHA256'
    )

    try {
        $actualHash = Get-FileHashExtended -Path $Path -Algorithm $Algorithm -ErrorAction SilentlyContinue

        if (-not $actualHash) {
            Write-Error "Failed to compute hash for verification."
            return $false
        }

        if ($actualHash.ToLower() -eq $ExpectedHash.ToLower()) {
            Write-Verbose "File integrity verified: Hash matches."
            return $true
        }

        Write-Warning "File integrity check failed: Hash mismatch."
        Write-Verbose "Expected: $($ExpectedHash.ToLower())"
        Write-Verbose "Actual:   $($actualHash.ToLower())"
        return $false
    }
    catch {
        Write-Error "Failed to verify file integrity: $_"
        return $false
    }
}

#endregion


#region Module Initialization

Export-ModuleMember -Function @(
    'Get-FileHashExtended',
    'Get-StringHash',
    'Test-FileIntegrity'
)

#endregion
