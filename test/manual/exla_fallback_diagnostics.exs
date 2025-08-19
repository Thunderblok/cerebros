IO.puts("🚀 Testing EXLA auto-fallback system")
IO.puts(String.duplicate("=", 40))

Code.require_file("lib/cerebros.ex")
Code.require_file("lib/cerebros/exla_helper.ex")

IO.puts("1️⃣  Diagnostics:")
Cerebros.ExlaHelper.diagnostics()

IO.puts("2️⃣  Setup best backend:")
backend = Cerebros.ExlaHelper.setup_best_backend()
IO.puts("Selected backend: #{backend}")

IO.puts("3️⃣  Quick test:")
Cerebros.ExlaHelper.quick_test()

if backend in [:cuda, :host] do
  IO.puts("4️⃣  (Placeholder) minimal NAS readiness: ✅")
end

IO.puts("🏁 Done")
