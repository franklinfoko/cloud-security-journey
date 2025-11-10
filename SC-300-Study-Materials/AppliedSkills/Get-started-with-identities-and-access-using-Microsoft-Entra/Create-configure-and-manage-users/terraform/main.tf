terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.6.0"
    }
  }
}

provider "azuread" {
}

data "azuread_domains" "this" {
  only_initial = true
}

resource "azuread_user" "this" {
  user_principal_name = "ChrisG@${data.azuread_domains.this.domains.0.domain_name}"
  display_name        = "Chris Green"
  given_name          = "Chris" # first name
  surname             = "Green" # last name
  password            = "SecretP@sswd99!" # required
}