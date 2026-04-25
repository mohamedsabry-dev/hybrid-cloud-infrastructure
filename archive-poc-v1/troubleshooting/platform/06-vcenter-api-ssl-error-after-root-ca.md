================================================================================
CASE: API SSL Errors Persist After Root CA Installation
================================================================================
Category: Platform - vCenter API/SDK Certificate Trust
Severity: Medium
Date: Post-Certificate Configuration
Environment: Python, PowerCLI, Ansible
Error: SSL Certificate Verification Failed

================================================================================
SYMPTOM
================================================================================
- API calls to vCenter fail with SSL verification errors
- Error persists after installing Root CA certificate in OS trust store
- Browser shows valid certificate, but scripts/tools fail
- Different behavior across Python, PowerCLI, and Ansible

Example Errors:
- Python: "SSL: CERTIFICATE_VERIFY_FAILED"
- PowerCLI: "The underlying connection was closed: Could not establish trust"
- Ansible: "certificate verify failed"

================================================================================
ROOT CAUSE ANALYSIS
================================================================================
Multiple certificate stores and trust mechanisms create complexity:

CAUSE 1: Python Requests Library Using Wrong Certificate Store
---------------------------------------------------------------
Python's requests library uses its own certificate bundle (certifi package)
instead of the OS certificate store. Installing CA in OS does not affect Python.

Certificate Resolution Order in Python:
1. Environment variable REQUESTS_CA_BUNDLE
2. Environment variable CURL_CA_BUNDLE
3. certifi package bundle (requests.certs.where())
4. NOT the OS certificate store

CAUSE 2: Ansible Using Python Without System Certificates
----------------------------------------------------------
Ansible runs on Python and inherits the same certificate store issues.
Additionally, Ansible may use different Python interpreters on control node
vs managed nodes.

CAUSE 3: PowerCLI Certificate Store Not Updated
------------------------------------------------
PowerCLI maintains its own certificate cache separate from Windows certificate
store. PowerShell session may have cached old certificate state.

================================================================================
DIAGNOSTIC PROCEDURES
================================================================================

Diagnosis 1: Identify Which Certificate Store is Used
------------------------------------------------------
Python diagnostic:
import requests
import certifi

print("Certifi bundle location:", certifi.where())
print("Environment REQUESTS_CA_BUNDLE:", os.getenv('REQUESTS_CA_BUNDLE'))

# Test connection
try:
    r = requests.get('https://vsphere.local/api/')
    print("Success:", r.status_code)
except Exception as e:
    print("Failed:", str(e))

Diagnosis 2: Verify Certificate Chain
--------------------------------------
openssl s_client -connect vsphere.local:443 -showcerts

Verify:
- Server certificate present
- Intermediate CA present (if any)
- Root CA matches installed CA

Diagnosis 3: Test with Certificate Validation Disabled
-------------------------------------------------------
# DIAGNOSTIC ONLY - Never use in production
curl -k https://vsphere.local/api/

If this works but normal requests fail, it's a trust store issue.

================================================================================
SOLUTIONS BY ROOT CAUSE
================================================================================

SOLUTION 1: Python Requests Library - Specify Certificate Bundle
-----------------------------------------------------------------

Option A: Add vCenter CA to Certifi Bundle
-------------------------------------------
import certifi
import os

# Locate certifi bundle
bundle_path = certifi.where()
print(f"Certifi bundle: {bundle_path}")

# Download vCenter Root CA
# From vCenter: https://vsphere.local/certs/download.zip
# Extract: certs/lin/xxx.0.crt

# Append to certifi bundle
vcenter_ca = '/path/to/vcenter-root-ca.crt'
with open(vcenter_ca, 'r') as ca_file:
    ca_content = ca_file.read()

with open(bundle_path, 'a') as bundle:
    bundle.write('\n')
    bundle.write('# vCenter Root CA\n')
    bundle.write(ca_content)

# Test
import requests
response = requests.get('https://vsphere.local/api/')
print(response.status_code)  # Should be 200

Option B: Use Custom Certificate Bundle
----------------------------------------
import requests
import certifi

# Create custom bundle
custom_bundle = '/etc/ssl/certs/custom-ca-bundle.crt'

# Method 1: Specify in request
response = requests.get('https://vsphere.local/api/', verify=custom_bundle)

# Method 2: Set environment variable
import os
os.environ['REQUESTS_CA_BUNDLE'] = custom_bundle
response = requests.get('https://vsphere.local/api/')

# Method 3: Set default for session
session = requests.Session()
session.verify = custom_bundle
response = session.get('https://vsphere.local/api/')

Option C: Use System Certificate Store (Python 3.10+)
------------------------------------------------------
# Python 3.10+ can use OS cert store with ssl.SSLContext
import ssl
import urllib.request

context = ssl.create_default_context()
context.load_default_certs()

with urllib.request.urlopen('https://vsphere.local/api/', context=context) as response:
    print(response.status)

SOLUTION 2: Ansible - Configure Certificate Bundle
---------------------------------------------------

Option A: Set Environment Variable
-----------------------------------
# In ansible.cfg
[defaults]
host_key_checking = False

[privilege_escalation]

# Set in environment
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# Run playbook
ansible-playbook -i inventory playbook.yml

Option B: Configure in Playbook
--------------------------------
- name: Configure vCenter connection
  vmware_guest:
    hostname: vsphere.local
    username: administrator@vsphere.local
    password: "{{ vcenter_password }}"
    validate_certs: true
  environment:
    REQUESTS_CA_BUNDLE: /etc/ssl/certs/ca-certificates.crt

Option C: Disable Certificate Validation (Lab Only)
----------------------------------------------------
# ONLY for closed lab environments
- name: Configure vCenter connection
  vmware_guest:
    hostname: vsphere.local
    username: administrator@vsphere.local
    password: "{{ vcenter_password }}"
    validate_certs: false

SOLUTION 3: PowerCLI - Update Certificate Store
------------------------------------------------

Option A: Restart PowerShell Session
-------------------------------------
1. Close all PowerShell windows
2. Open new PowerShell session
3. Re-import modules:
   Import-Module VMware.PowerCLI

4. Test connection:
   Connect-VIServer -Server vsphere.local

Option B: Set Certificate Configuration
----------------------------------------
# Set PowerCLI to use OS certificate store
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Scope User

# Or for specific session
Set-PowerCLIConfiguration -InvalidCertificateAction Warn -Scope Session

# For production with valid certs
Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Scope User

Option C: Clear PowerCLI Cache
-------------------------------
# Remove cached certificate data
$env:PSMODULEPATH -split ';' | ForEach-Object {
    $cachePath = Join-Path $_ 'VMware.VimAutomation.Sdk\Cache'
    if (Test-Path $cachePath) {
        Remove-Item $cachePath -Recurse -Force
    }
}

# Restart PowerShell
# Reconnect to vCenter

================================================================================
VERIFICATION PROCEDURES
================================================================================

Python Verification:
--------------------
import requests
response = requests.get('https://vsphere.local/api/')
assert response.status_code == 200
print("Yes Python SSL verification working")

Ansible Verification:
---------------------
ansible localhost -m uri -a "url=https://vsphere.local/api/ validate_certs=yes"

Expected: Success (HTTP 200)

PowerCLI Verification:
----------------------
Connect-VIServer -Server vsphere.local
Get-VM | Select-Object Name -First 1
Disconnect-VIServer -Confirm:$false

Expected: Successful connection and VM listing

================================================================================
PREVENTION
================================================================================
1. Document certificate bundle locations for all tools/languages
2. Create standard certificate bundle for organization
3. Set environment variables in user/system profiles
4. Test API access after any certificate changes
5. Maintain scripts for certificate distribution
6. Use configuration management for certificate bundles
7. Document certificate validation settings per tool

================================================================================
COMPLETE ENVIRONMENT SETUP
================================================================================

For Comprehensive Certificate Trust:
-------------------------------------
# 1. Install Root CA in OS
# Windows: certmgr.msc → Trusted Root CA
# Linux: /usr/local/share/ca-certificates/ → update-ca-certificates
# macOS: Keychain Access → System → Certificates

# 2. Set Python environment variables (~/.bashrc or ~/.zshrc)
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# 3. Update certifi bundle (Python)
cat /path/to/vcenter-ca.crt >> $(python3 -c "import certifi; print(certifi.where())")

# 4. Configure Ansible (ansible.cfg)
[defaults]
host_key_checking = False

# 5. Configure PowerCLI (PowerShell profile)
Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Scope User -Confirm:$false

# 6. Test all tools
python3 -c "import requests; print(requests.get('https://vsphere.local/api/').status_code)"
ansible localhost -m uri -a "url=https://vsphere.local/api/"
pwsh -Command "Connect-VIServer -Server vsphere.local"

================================================================================
REFERENCES
================================================================================
Source: /DC-K8s/.archive/00-HOST-FOUNDATION/01-vcenter/05-troubleshooting.md
Related Cases: 04-vCenter-Certificate-Browser-Error, 05-vCenter-Certificate-Manager-Replace-Failed
Python Requests Docs: https://requests.readthedocs.io/en/latest/user/advanced/#ssl-cert-verification
Ansible Docs: https://docs.ansible.com/ansible/latest/reference_appendices/config.html
PowerCLI Docs: VMware PowerCLI Certificate Configuration

================================================================================
LESSONS LEARNED
================================================================================
- Browser trust ≠ Programming language trust
- Each language/tool maintains separate certificate stores
- OS certificate store is often NOT the default for tools
- Environment variables are key to certificate configuration
- Testing must cover all tools in the toolchain, not just browsers
- Certificate trust is a cross-cutting concern requiring systematic approach
- Documentation of certificate locations is critical
- Lab environments can disable validation; production must not
- Certificate bundle updates may require tool/session restarts
