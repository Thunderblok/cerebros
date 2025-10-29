defmodule Thunderline.Ledger do
  use Ash.Domain,
    otp_app: :thunderline

  resources do
    resource Thunderline.Ledger.Account
    resource Thunderline.Ledger.Balance
    resource Thunderline.Ledger.Transfer
  end
end
