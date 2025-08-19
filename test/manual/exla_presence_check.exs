System.put_env("EXLA_TARGET", "host")

if Code.ensure_loaded?(EXLA.Backend) do
  IO.puts("✅ EXLA.Backend module present")
else
  IO.puts("❌ EXLA.Backend module NOT loaded")
end

path = "_build/dev/lib/exla/priv/libexla.so"
if File.exists?(path) do
  IO.puts("✅ Found #{path}")
else
  IO.puts("❌ Missing #{path}")
end
