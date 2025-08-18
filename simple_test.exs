System.put_env("EXLA_TARGET", "host")

# Try to load EXLA
try do
  Code.ensure_loaded(EXLA.Backend)
  IO.puts("✅ EXLA.Backend loaded successfully")
rescue
  e -> IO.puts("❌ Failed to load EXLA.Backend: #{inspect(e)}")
end

# Check if the library file exists
if File.exists?("_build/dev/lib/exla/priv/libexla.so") do
  IO.puts("✅ libexla.so found in build directory")
else
  IO.puts("❌ libexla.so not found in build directory")
end