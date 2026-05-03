# Run the docker script first. because of docker add group depednancy
import subprocess
USERNAME = "admin"

###########################################################################
###########################################################################
def enable_user_pass():
    try:
        subprocess.run(f"echo -e 'Match User {USERNAME}\n    PasswordAuthentication yes' > /etc/ssh/sshd_config.d/99-admin-password.conf", shell=True, check=True)
        subprocess.run(["systemctl", "restart", "sshd"], check=True)
    except Exception as e:
        print ('Failed to enable password auth', e)
        return    
###########################################################################
###########################################################################
def force_password_change(username):
    try:
        subprocess.run(f"echo 'passwd && sed -i \"/passwd/d\" ~/.bash_profile' >> /home/{username}/.bash_profile", shell=True, check=True)
    except Exception as e:
          print("Failed to set forced password change:", e)
          return
###########################################################################
###########################################################################
def create_user():
    try:
        subprocess.run(["useradd","-m","-s","/bin/bash",USERNAME],check=True)
        subprocess.run(f"echo '{USERNAME}:Change_Me' | chpasswd", shell=True, check=True)
        subprocess.run(["usermod","-aG","wheel,docker",USERNAME],check=True)
    except Exception as e:
        print ('Failed to create user', e)
        return
###########################################################################
###########################################################################
def main():
    enable_user_pass()
    create_user()
    force_password_change(USERNAME)


if __name__ == "__main__":
    main()