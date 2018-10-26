function Invoke-Redaction {
    <#
    .SYNOPSIS
    Redact a string object
    
    .DESCRIPTION
    Redact a string object
    
    .PARAMETER InputObject
    An Input Object to redact from
    
    .PARAMETER ReductionRule
    Array of Rules with Regex pattern and new value to set when this pattern is matched to input object 
    
    .PARAMETER LineNumber
    Line number is used as a seed to obfoscate new values
    
    .PARAMETER Consistent
    Use a ConvertionTable to make previously matched values assigned with the same new valuethat was assigned to them and theyr were first found to make consistent
    
    .PARAMETER ConvertionTable
    Table contains the matched values and their replacements
    
    .PARAMETER AsObject
    Return object with more parameters instead of single string 
    
    .EXAMPLE
    An example
    
    .NOTES
    General notes
    #>
    [Alias('Invoke-Sanitization','irduc','isntz')]
    [CmdletBinding()]
    param(
        # One line string
        [Parameter(Mandatory = $true, 
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true, 
            Position = 0)]
        [Alias("CurrentString")]
        [AllowEmptyString()] # Incoming lines can be empty, so applied because of the Mandatory flag
        [psobject]
        $InputObject,
        [Parameter(Mandatory = $true, 
            Position = 1)]
        [RedactionRule[]]$RedactionRule,
        # Good practice is to provide the value from outside and increment before this function is being called for a new line.
        # If $LineNumber is not provided it is set to 0.
        [Parameter(ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true, 
            Position = 2)]
        [int]$LineNumber,
        # Requires $ConvertionTable but if it won't be provided, empty hash table for $ConvertionTable will be initialized instead
        [Parameter(Position = 3,
            ParameterSetName = 'Consistent')]
        [switch]
        $Consistent,
        [Parameter(Position = 4,
            ParameterSetName = 'Consistent')]
        [HashTable]
        $ConvertionTable,
        [switch]
        $AsObject,
        [switch]
        $ShowProgress,
        [int]
        $TotalLines)

    Begin {
        if (-not $LineNumber) {
            $LineNumber = 0
        }

        if ($Consistent) {
            $Uniqueness = 0
            if (-not $ConvertionTable) {
                $ConvertionTable = @{}
            }
        }

        #region Write-Progress calculation block initialization
        if($ShowProgress) {
            $PercentComplete = 0
            $PercentStep = 100 / $TotalLines
            [double]$AverageTime = 0
            [int]$SecondsRemaining = $AverageTime * $TotalLines
            $StopWatch = [System.Diagnostics.Stopwatch]::new()
            $StopWatch.Start()
        }
        #endregion
    }

    Process {
        $CurrentString = $InputObject.ToString()
        $CurrentStringChanged = $false

        foreach ($Rule in $RedactionRule) {
            # Consistent
            $Matches = Select-String -InputObject $CurrentString -Pattern $Rule.Pattern -AllMatches | Select-Object -ExpandProperty Matches | Sort-Object -Property Index -Descending # Sort Descending is required so the replacments won't overwrite each other
            if ($Matches) {
                $CurrentStringChanged = $true
                $StrSB = New-Object System.Text.StringBuilder($CurrentString)
                Foreach ($Match in $Matches) {
                    $MatchedValue = $Match.Value

                    'MatchedValue = {0}' -f $MatchedValue | Write-Verbose

                    if ($Consistent) {
                        if ($null -eq $ConvertionTable[$MatchedValue]) {
                            # MatchedValue doesn't exist in the ConvertionTable
                            # Adding MatchedValue to the ConvertionTable, add it with line number (if {0} is specified in $NewValue)
                            $ConvertionTable[$MatchedValue] = $Rule.Evaluate($Uniqueness)
                            'Adding new value to the convertion table: $ConvetionTable[{0}] = {1}' -f $MatchedValue, $ConvertionTable[$MatchedValue] | Write-Verbose 
                            $Uniqueness++
                        }

                        # This MatchedValue exists, use it.
                        $Replacement = $ConvertionTable[$MatchedValue]
                    }
                    else {
                        $Replacement = $Rule.Evaluate($LineNumber)
                    }

                    $null = $StrSB.Remove($Match.Index, $Match.Length)
                    $null = $StrSB.Insert($Match.Index, $Replacement)
                }

                $CurrentString = $StrSB.ToString()
            }
        } # foreach($Rule in $ReductionRule)

        # Only if result is different from the input object
        if ($AsObject) {
            $OutputProperties = @{
                LineNumber    = $LineNumber
                CurrentString = $CurrentString
                Original      = $InputObject
                Changed       = $CurrentStringChanged
            }

            $OutputPropertiesList = 'LineNumber', 'CurrentString', 'Original', 'Changed'

            if ($Consistent) {
                $OutputProperties['Uniqueness'] = $Uniqueness
                $OutputPropertiesList += 'Uniqueness'
            }

            New-Object -TypeName PSCustomObject -Property $OutputProperties | Select-Object $OutputPropertiesList
        }
        else {
            $CurrentString
        }

        #region Write-Progress calculation block
        if($ShowProgress) {
            $PercentComplete += $PercentStep
            $ElapsedSeconds = $StopWatch.Elapsed.TotalSeconds
            $StopWatch.Restart()
            [double]$AverageTime = ($AverageTime * $Line + $ElapsedSeconds) / ($Line + 1)
            [int]$SecondsRemaining = $AverageTime * ($TotalLines - $Line)
            'L = {0} | Avg = {1} | Remain(S) = {2}' -f $Line, $AverageTime, $ElapsedSeconds, $SecondsRemaining | Write-Debug
            Write-Progress -Activity "Redacting sensitive data" -Id 1 -ParentId 2 -PercentComplete $PercentComplete -SecondsRemaining $SecondsRemaining
        }
        #endregion

        $LineNumber++
    } # Process

    end {
        #region Write-Progress calculation block closing
        if($ShowProgress) {
            $StopWatch.Stop()        
            Write-Progress -Activity "[Done] Redacting sensitive data [Done]" -Id 1 -ParentId 2 -Completed
        }
        #endregion
    }
}
