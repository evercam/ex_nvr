NervesMOTD.print()

# Add Toolshed helpers to the IEx session
use Toolshed

if RamoopsLogger.available_log?() do
  IO.puts("Oops! There's something in the oops log. Check with RamoopsLogger.dump()")
end
