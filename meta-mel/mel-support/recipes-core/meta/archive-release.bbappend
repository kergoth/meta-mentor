FILESEXTRAPATHS_append = ":${@':'.join('%s/../scripts/release' % l for l in '${BBPATH}'.split(':'))}"
SRC_URI += "\
    file://mel-checkout \
    file://setup-environment \
"

PDK_DISTRO_VERSION ?= "${DISTRO_VERSION}"
MANIFEST_NAME ?= "${DISTRO}-${PDK_DISTRO_VERSION}-${MACHINE}"

python do_archive_mel_layers () {
    """Archive the layers used to build, as git pack files, with a manifest."""

    directories = d.getVar('BBLAYERS').split()
    bitbake_path = bb.utils.which(d.getVar('PATH'), 'bitbake')
    bitbake_bindir = os.path.dirname(bitbake_path)
    directories.append(os.path.dirname(bitbake_bindir))

    corebase = os.path.realpath(d.getVar('COREBASE'))
    oedir = os.path.dirname(corebase)
    topdir = os.path.realpath(d.getVar('TOPDIR'))
    indiv_only = d.getVar('SUBLAYERS_INDIVIDUAL_ONLY').split()
    indiv_only_toplevel = d.getVar('SUBLAYERS_INDIVIDUAL_ONLY_TOPLEVEL').split()

    to_archive = set()
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

    outdir = d.expand('${S}/deploy')
    mandir = os.path.join(outdir, 'manifests')
    bb.utils.mkdirhier(mandir)
    objdir = os.path.join(outdir, 'objects', 'pack')
    bb.utils.mkdirhier(objdir)
    manifestfn = d.expand('%s/${MANIFEST_NAME}.manifest' % mandir)
    with open(manifestfn, 'w') as manifest:
        for subdir, path in sorted(to_archive):
            pack_base, head = git_archive(subdir, objdir, '%s version %s' % (d.getVar('DISTRO'), d.getVar('PDK_DISTRO_VERSION')))
            manifest.write('%s\t%s\t%s\n' % (path, pack_base, head))
            bb.process.run(['tar', '-cf', '%s.tar' % pack_base, 'objects/pack/%s.pack' % pack_base, 'objects/pack/%s.idx' % pack_base], cwd=outdir)

    bb.process.run(['tar', '-cf', os.path.basename(manifestfn) + '.tar', 'manifests'], cwd=outdir)
    bb.process.run(['mv', manifestfn, outdir])
    bb.process.run(['rm', '-r', 'manifests'], cwd=outdir)
    bb.process.run(['rm', '-r', 'objects'], cwd=outdir)
    bb.process.run(['tar', '-cf', d.expand('%s/${DISTRO}-scripts.tar' % outdir), 'mel-checkout', 'setup-environment'], cwd=d.getVar('WORKDIR'))
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
        if parent:
            head = bb.process.run(gitcmd + ['commit-tree', '-m', message, '-p', parent_head, tree])[0].rstrip()
            with open(os.path.join(tmpdir, 'shallow'), 'w') as f:
                f.write(head + '\n')
        else:
            head = bb.process.run(gitcmd + ['commit-tree', '-m', message, tree])[0].rstrip()

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
        return base, head

