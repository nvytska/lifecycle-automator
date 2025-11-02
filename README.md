# Assignment 2: Git Repository Lifecycle Automator
Student: Nataliia Vytska
Group: SE530 Group 1

---

**How to use script:**
1. Clone repo: ```git clone https://github.com/nvytska/lifecycle-automator.git```
2. Create a clear environment to test: ```mkdir ~/git-tests && cd ~/git-tests```
3. Copy script and make it executable: ```cp ../lifecycle-automator/repo-lifecycle.sh .```
```chmod +x repo-lifecycle.sh```
4. Run script with arguments you want to:
   ```./repo-lifecycle.sh [repo_path] [command]```,
   or w/o arguments to get into interactive menu:
   ```./repo-lifecycle.sh```.

**Availiable commands:**
| command | description |
|---------|-------------|
| create | Initializes a git repo, with project name, default branch name, initial commit, sets up commit template, hook, and adds submodules |
| validate | Checks if some existing commits does not match template |
| submodule_check | Scans all submodules, looking for diffs and local cahnges |


