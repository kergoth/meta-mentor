FILESEXTRAPATHS_append = ":${@':'.join('%s/../scripts/release' % l for l in '${BBPATH}'.split(':'))}"
SRC_URI += "\
    file://mel-checkout \
    file://setup-environment \
"

inherit layerdirs

# Layers which get their own extra manifests, rather than being included in
# the main one. How they're combined or shipped from there is up to our
# release scripts.
INDIVIDUAL_MANIFEST_LAYERS ?= " \
    update-* \
    mel-security* \
    selinux \
    mentor-softing* \
    meta-mentor-industrial* \
    meta-mentor-iot* \
    meta-fastboot* \
"
PDK_DISTRO_VERSION ?= "${DISTRO_VERSION}"
MANIFEST_NAME ?= "${DISTRO}-${PDK_DISTRO_VERSION}-${MACHINE}"
BSPFILES_INSTALL_PATH = "${MACHINE}/${PDK_DISTRO_VERSION}"

python do_archive_mel_layers () {
    """Archive the layers used to build, as git pack files, with a manifest."""
    import collections
    import configparser
    import fnmatch

    directories = d.getVar('BBLAYERS').split()
    bitbake_path = bb.utils.which(d.getVar('PATH'), 'bitbake')
    bitbake_bindir = os.path.dirname(bitbake_path)
    directories.append(os.path.dirname(bitbake_bindir))

    corebase = os.path.realpath(d.getVar('COREBASE'))
    oedir = os.path.dirname(corebase)
    topdir = os.path.realpath(d.getVar('TOPDIR'))
    indiv_only = d.getVar('SUBLAYERS_INDIVIDUAL_ONLY').split()
    indiv_only_toplevel = d.getVar('SUBLAYERS_INDIVIDUAL_ONLY_TOPLEVEL').split()
    indiv_manifests = d.getVar('INDIVIDUAL_MANIFEST_LAYERS').split()

    layernames = {}
    for layername in d.getVar('BBFILE_COLLECTIONS').split():
        layerdir = d.getVar('LAYERDIR_%s' % layername)
        if layerdir:
            layernames[layerdir] = layername

    to_archive, indiv_manifest_dirs = set(), set()
    path = d.getVar('PATH') + ':' + ':'.join(os.path.join(l, '..', 'scripts') for l in directories)
    for subdir in directories:
        subdir = os.path.realpath(subdir)
        parent = os.path.dirname(subdir)
        relpath = None
        if (subdir not in indiv_only and
                not os.path.exists(os.path.join(subdir, '.git')) and
                parent not in (oedir, topdir) and
                os.path.exists(os.path.join(parent, '.git'))):
            ls = bb.process.run(['git', 'ls-tree', '-d', 'HEAD', subdir], cwd=parent)
            if ls:
                to_archive.add((parent, os.path.basename(parent)))
                continue

        if (subdir not in indiv_only_toplevel and
                not subdir.startswith(topdir + os.sep) and
                subdir.startswith(oedir + os.sep)):
            to_archive.add((subdir, os.path.relpath(subdir, oedir)))
        else:
            to_archive.add((subdir, os.path.basename(subdir)))

        layername = layernames.get(subdir)
        if layername and any(fnmatch.fnmatchcase(layername, pat) for pat in indiv_manifests):
            indiv_manifest_dirs.add(subdir)

    outdir = d.expand('${S}/deploy')
    mandir = os.path.join(outdir, 'manifests')
    bb.utils.mkdirhier(mandir)
    bb.utils.mkdirhier(os.path.join(mandir, 'extra'))
    objdir = os.path.join(outdir, 'objects', 'pack')
    bb.utils.mkdirhier(objdir)
    manifestfn = d.expand('%s/${MANIFEST_NAME}.manifest' % mandir)
    manifests = [manifestfn]
    message = '%s release' % d.getVar('DISTRO')

    manifestdata = collections.defaultdict(list)
    for subdir, path in sorted(to_archive):
        pack_base, head, remote = git_archive(subdir, objdir, message)
        if subdir in indiv_manifest_dirs:
            fn = d.expand('%s/extra/${MANIFEST_NAME}-%s.manifest' % (mandir, path.replace('/', '_')))
        else:
            fn = manifestfn
        manifestdata[fn].append('\t'.join((path, head, remote)) + '\n')
        bb.process.run(['tar', '-cf', '%s.tar' % pack_base, 'objects/pack/%s.pack' % pack_base, 'objects/pack/%s.idx' % pack_base], cwd=outdir)

    infofn = d.expand('%s/${MANIFEST_NAME}.info' % mandir)
    with open(infofn, 'w') as infofile:
        c = configparser.ConfigParser()
        c['DEFAULT'] = {'bspfiles_path': d.getVar('BSPFILES_INSTALL_PATH')}
        c.write(infofile)

    for fn, lines in manifestdata.items():
        with open(fn, 'w') as manifest:
            manifest.writelines(lines)
            files = [os.path.relpath(fn, outdir)]
            if fn == manifestfn:
                files.append(os.path.relpath(infofn, outdir))
        bb.process.run(['tar', '-cf', os.path.basename(fn) + '.tar'] + files, cwd=outdir)

    bb.process.run(['rm', '-r', 'objects'], cwd=outdir)

    workdir = d.getVar('WORKDIR')
    with open(os.path.join(workdir, 'setup-mel'), 'w') as sm:
        with open(os.path.join(workdir, 'mel-checkout'), 'r') as mc:
            with open(os.path.join(workdir, 'setup-environment'), 'r') as se:
                sm.write('mel_checkout () {\n')
                sm.write('  (\n')
                sm.write(mc.read())
                sm.write('  )\n')
                sm.write('}\n')
                sm.write(se.read().replace('"$scriptdir/mel-checkout"', 'mel_checkout'))
                sm.write('unset mel_checkout')
    bb.process.run(['chmod', '+x', 'setup-mel'], cwd=workdir)
    bb.process.run(['tar', '-cf', d.expand('%s/${DISTRO}-scripts.tar' % outdir), 'setup-mel'], cwd=workdir)
}
do_archive_mel_layers[vardepsexclude] += "DATE"
addtask archive_mel_layers after do_patch

def git_archive(subdir, outdir, message=None):
    """Create an archive for the specified subdir, holding a single git object

    1. Clone or create the repo to a temporary location
    2. Make the repo shallow
    3. Repack the repo into a single git pack
    4. Copy the pack files to outdir
    """
    import glob
    import tempfile
    if message is None:
        message = 'Release of %s' % os.path.basename(subdir)
    # Should we try using the PR Server for versioning?
    # FIXME: if the temporary dir is on a different fs than the source
    # repository, this could be quite slow
    if os.path.exists(os.path.join(subdir, '.git')):
        parent = subdir
    else:
        parent = None

    with tempfile.TemporaryDirectory() as tmpdir:
        gitcmd = ['git', '--git-dir', tmpdir, '--work-tree', subdir]
        bb.process.run(gitcmd + ['init'])
        if parent:
            with open(os.path.join(tmpdir, 'objects', 'info', 'alternates'), 'w') as f:
                f.write(os.path.join(parent, '.git', 'objects') + '\n')
            parent_head = bb.process.run(['git', 'rev-parse', 'HEAD'], cwd=subdir)[0].rstrip()
            bb.process.run(gitcmd + ['read-tree', parent_head])

        bb.process.run(gitcmd + ['add', '-A', '.'], cwd=subdir)
        tree = bb.process.run(gitcmd + ['write-tree'])[0].rstrip()

        env = {
            'GIT_AUTHOR_NAME': 'Build User',
            'GIT_AUTHOR_EMAIL': 'build_user@build_host',
            'GIT_COMMITTER_NAME': 'Build User',
            'GIT_COMMITTER_EMAIL': 'build_user@build_host',
        }
        if parent:
            remote = bb.process.run(['git', 'config', 'remote.origin.url'], cwd=subdir)[0].rstrip()

            # Walk the commits until we get a date, as merges don't seem to
            # report a commit date.
            cdate, distance = None, 0
            while not cdate:
                try:
                    cdate = bb.process.run(['git', 'diff-tree', '--pretty=format:%ct', '-s', 'HEAD~%d' % distance], cwd=subdir)[0]
                except bb.process.CmdError:
                    break
                distance += 1

            penv = dict(env)
            if cdate:
                penv.update(GIT_AUTHOR_DATE=cdate, GIT_COMMITTER_DATE=cdate)

            head = bb.process.run(gitcmd + ['commit-tree', '-m', message, '-p', parent_head, tree], env=penv)[0].rstrip()
            with open(os.path.join(tmpdir, 'shallow'), 'w') as f:
                f.write(head + '\n')
        else:
            remote = ''
            head = bb.process.run(gitcmd + ['commit-tree', '-m', message, tree], env=env)[0].rstrip()

        # We need a ref to ensure repack includes the new commit, as it
        # does not include dangling objects in the pack.
        bb.process.run(['git', 'update-ref', 'refs/packing', head], cwd=tmpdir)
        bb.process.run(['git', 'prune', '--expire=now'], cwd=tmpdir)
        bb.process.run(['git', 'repack', '-a', '-d'], cwd=tmpdir)
        bb.process.run(['git', 'prune-packed'], cwd=tmpdir)

        packdir = os.path.join(tmpdir, 'objects', 'pack')
        packfiles = glob.glob(os.path.join(packdir, 'pack-*'))
        base, ext = os.path.splitext(os.path.basename(packfiles[0]))
        bb.process.run(['cp', '-f'] + packfiles + [outdir])
        return base, head, remote

