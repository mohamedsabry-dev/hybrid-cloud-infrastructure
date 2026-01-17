resource "aws_iam_user" "console_admin"  {
    name = var.console_admin
    path = "/system/"
}

resource "aws_iam_user_policy_attachment" "console_admin_attach" {
    user       = aws_iam_user.console_admin.name
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


# Create the User and Attach the Policy
resource "aws_iam_user" "tf_state_admin" {
  name = var.tf_state_admin
}

resource "aws_iam_user_policy_attachment" "tf_state_admin_attach" {
  user       = aws_iam_user.tf_state_admin.name
  policy_arn = aws_iam_policy.tf_management_policy.arn
}