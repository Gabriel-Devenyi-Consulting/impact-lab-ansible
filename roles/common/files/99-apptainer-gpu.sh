# Expose the host's NVIDIA driver stack to Apptainer containers
#
# A container carries its own userspace GL and CUDA libraries. Neurodesk's
# images ship Mesa's GLX vendor library but not NVIDIA's, which leaves two
# gaps:
#
#   * Graphics only work while the X server's GLX vendor is Mesa. libglvnd
#     asks the server which vendor it speaks, then dlopen()s
#     libGLX_<vendor>.so.0 from inside the container. Whichever GPU drives the
#     monitor decides that answer, so plugging the display into the NVIDIA card
#     makes the server answer "nvidia", the lookup fail, and every OpenGL
#     application — fsleyes included — die.
#   * CUDA tools cannot run at all. libcuda.so.1 ships with the driver, never
#     in an image, so FSL's eddy_cuda and bedpostx_gpu have nothing to bind to.
#
# --nv makes Apptainer bind the host's NVIDIA libraries (listed in
# /etc/apptainer/nvliblist.conf) into the container. APPTAINER_NV is the
# environment-variable form of that flag, so it applies to every container
# launch including the Neurodesk module wrappers on CVMFS, which we do not
# control.
#
# Setting it unconditionally is safe: libglvnd loads the vendor the X server
# names, so while Mesa is driving the display the NVIDIA library is simply
# never opened. That is what makes this cover both cable configurations rather
# than trading one for the other.
#
# The cost is binding those libraries on every container launch, measured at
# roughly +19ms (35ms -> 54ms for `exec ... true`). Irrelevant for a GUI, and
# small against any real fslmaths call, but it is per-invocation: a script that
# shells out to a container tool 10k times in a loop pays about three minutes
# for it. Set APPTAINER_NV=0 to opt such a job — or any single command — out.
#
# Gated on the kernel module being loaded, so it stays inert on hosts with no
# NVIDIA GPU.
if [ -f /proc/driver/nvidia/version ] && [ -z "${APPTAINER_NV+set}" ]; then
    export APPTAINER_NV=1
fi
