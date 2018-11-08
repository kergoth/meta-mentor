# This class provides a hook to set variables in the SDK environment-setup
# script to the values they have at image construction time, rather than the
# values they had in meta-environment.
SDK_RESET_ENV_SCRIPT_VARS ?= ""

inherit sdk_multilib_hook

SDK_POSTPROCESS_MULTILIB_COMMAND += "adjust_environment_script;"

adjust_environment_script () {
    script="${SDK_ENV_SETUP_SCRIPT}"
    if [ ! -e "$script" ]; then
        bbwarn "adjust_environment_script: $script does not exist"
        return
    fi
    while read -r var value; do
        if [ -n "$var" ]; then
            sed -Ei -e "/(export )?$var=/s/=.*/=\"$value\"/" "$script"
        fi
    done <<END
${@shell_get_vars(d, '${SDK_RESET_ENV_SCRIPT_VARS}')}
END
}
adjust_environment_script[vardeps] += "${SDK_RESET_ENV_SCRIPT_VARS}"

def shell_get_vars(d, bbvars):
    """Return var/value pairs for use in a shell while loop.

    Example usage:

    while read -r var value; do
    done <<END
    $'{@shell_get_vars(d, 'FOO BAR')}
    END
    """
    if isinstance(bbvars, str):
        bbvars = bbvars.split()
    lines = []
    for var in bbvars:
        lines.append('{0} {1}\n'.format(var, d.getVar(var, True)))
    return ''.join(lines)

def shell_vars(d, bbvars, indent='    '):
    """Return var=value lines to set them as shell variables."""
    import subprocess
    if isinstance(bbvars, str):
        bbvars = bbvars.split()
    lines = []
    for var in bbvars:
        value = d.getVar(var, True)
        lines.append('{0}{1}={2}\n'.format(indent, var, subprocess.list2cmdline([value])))
    return ''.join(lines)[len(indent):]
