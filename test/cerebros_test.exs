defmodule CerebrosTest do
  use ExUnit.Case
  doctest Cerebros

  test "greets the world" do
    assert Cerebros.hello() == :world
  end
end
