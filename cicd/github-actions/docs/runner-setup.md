Runners

Add new self-hosted runner · mohamedsabry-dev/hybrid-cloud-infrastructure

Add new self-hosted runner · mohamedsabry-dev/hybrid-cloud-infrastructure

Adding a self-hosted runner requires that you download, configure, and execute the GitHub Actions Runner. If you do not already have an existing volume licensing agreement for your GitHub purchases, by downloading and configuring the GitHub Actions Runner, you agree to the GitHub Customer Agreement.

Runner image

macOS

Architecture ARM

Download

# Create a folder
$ mkdir actions-runner && cd actions-runner

# Download the latest runner package
$ curl -o actions-runner-osx-arm64-2.331.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-osx-arm64-2.331.0.tar.gz

# Optional: Validate the hash
$ echo "6f56ce368b09041f83c5ded4d0fb83b08d9a28e22300a2ce5cb1ed64e67ea47c actions-runner-osx-arm64-2.331.0.tar.gz" | shasum -a 256 -c

# Extract the installer
$ tar xzf ./actions-runner-osx-arm64-2.331.0.tar.gz

Configure

# Create the runner and start the configuration experience
$ ./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure --token B4YOKZ6UQAYGQTNLUMAB3F3JN7TJA

# Last step, run it!
$ ./run.sh

Using your self-ho