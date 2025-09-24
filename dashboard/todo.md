ok. I want now to refactor install_comfyui.sh. Extract in script/:
- the installation of comfy-ui
- the creation of the a new conda environment (with a unique suffix = datetime)
- make the install of torch/nvidia not with  pip install, but with conda, to make these dependencies shared between conda environments.
- do not make changes in .bashrc
- create a service with eponym name, but not automatically started 
- 