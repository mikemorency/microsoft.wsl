[windows]
wsl_test_host ansible_host=$WSL_HOSTNAME

[windows:vars]
ansible_user=$WSL_USERNAME
ansible_password=$WSL_PASSWORD
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_port=${WSL_PORT:-5985}
ansible_winrm_scheme=${WSL_WINRM_SCHEME:-http}

# support winrm connection tests (temporary solution, does not support testing enable/disable of pipelining)
[winrm:children]
windows

# support tests that target testhost
[testhost:children]
windows
