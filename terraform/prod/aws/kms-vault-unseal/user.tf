resource "aws_iam_user" "vault_unseal" {
  name = "vault-unseal"
  path = "/system/"

  tags = {
    Name    = "vault-unseal-user"
    Purpose = "vault-auto-unseal"
  }
}

resource "aws_iam_access_key" "vault_unseal" {
  user = aws_iam_user.vault_unseal.name
}
