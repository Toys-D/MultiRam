#!/usr/bin/env python3
"""Package a universal MultiRam release using macOS system tools.

Signs ad hoc by default. With --identity, signs with that certificate instead: its designated
requirement names the certificate rather than the binary hash, so the Accessibility permission
survives updates signed with the same certificate."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True).stdout


# On macOS 27 a fresh build can carry the system "restricted" file flag. ditto and cp -p copy
# file flags, and setting that one fails with "Operation not permitted", so bundles are copied
# with plain cp -R: symbolic links stay links, modes and extended attributes come along.
def copy_bundle(source, destination):
    run('cp', '-R', source, destination)


def run_stderr(*args):
    # codesign prints signature details to standard error.
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True).stderr.decode()


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def validate_dependencies(executable):
    # Hardened Runtime cannot load a third-party framework signed by another team, or ad hoc
    # with no Team ID. A successful codesign verification does not detect this.
    dependencies = run('otool', '-L', executable).decode().splitlines()
    unsupported = {
        line.strip().split(' (compatibility version', 1)[0]
        for line in dependencies
        if line.startswith('\t') and not line.strip().startswith(('/System/Library/', '/usr/lib/'))
    }
    if unsupported:
        raise SystemExit(
            'Cannot package this release with non-system dynamic dependencies: '
            + ', '.join(sorted(unsupported))
            + '. Remove the unused dependency or use Developer ID distribution signing.'
        )


def resolve_identity(identity):
    """Find the one valid signing certificate codesign would pick: a SHA-1 hash or part of the name."""
    listing = run('security', 'find-identity', '-v', '-p', 'codesigning').decode()
    identities = re.findall(r'^\s*\d+\) ([0-9A-F]{40}) "(.+)"$', listing, re.M)
    if re.fullmatch(r'[0-9A-Fa-f]{40}', identity):
        matches = [(sha1, name) for sha1, name in identities if sha1 == identity.upper()]
    else:
        matches = [(sha1, name) for sha1, name in identities if name == identity]
        matches = matches or [(sha1, name) for sha1, name in identities if identity in name]
    if len(set(matches)) != 1:
        raise SystemExit(f'Expected exactly one valid signing identity for {identity!r}, found {len(set(matches))}.')
    return matches[0]


def signing_texts(certificate_name):
    if certificate_name is None:
        return {
            'note': '',
            'status': 'Этот релиз подписан ad hoc, без Developer ID и заверения Apple.',
            'english': 'This ad hoc signed release is not notarized.',
        }
    kind = certificate_name.split(':', 1)[0]
    if kind in ('Apple Development', 'Mac Developer'):
        status = 'Этот релиз подписан сертификатом разработчика Apple Development, ' \
                 'но не заверен Apple (без Developer ID и нотаризации).'
        english = 'This release is signed with an Apple Development certificate and is not notarized.'
    elif kind == 'Developer ID Application':
        status = 'Этот релиз подписан сертификатом Developer ID, но не заверен Apple (без нотаризации).'
        english = 'This release is signed with a Developer ID certificate and is not notarized.'
    else:
        raise SystemExit(f'No install instructions for a {kind!r} certificate.')
    return {
        'note': 'Обновления с той же подписью разрешение не сбрасывают.\n',
        'status': status,
        'english': english + ' Updates with the same signature keep the Accessibility permission.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--checkouts', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--identity', default='-',
                        help='code signing identity; "-" (default) signs ad hoc')
    args = parser.parse_args()
    source = args.app.resolve()
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'local.multiram.MultiRam':
        raise SystemExit('Expected the MultiRam application bundle.')
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise SystemExit('Expected a three-part release version.')
    release_name = '1.0' if version == '1.0.0' else version
    if args.output is None:
        args.output = ROOT / 'releases' / f'MultiRam-{release_name}'
    executable = source / 'Contents/MacOS' / info['CFBundleExecutable']
    validate_dependencies(executable)
    adhoc = args.identity == '-'
    # Resolve before writing anything, so a wrong identity leaves no partial output behind.
    certificate_sha1, certificate_name = (None, None) if adhoc else resolve_identity(args.identity)
    if list((source / 'Contents/Frameworks').glob('*.framework')):
        raise SystemExit('Unexpected embedded framework in the portable release; use a clean build.')
    architectures = run('lipo', '-archs', executable).decode().split()
    if set(architectures) != {'arm64', 'x86_64'}:
        raise SystemExit('A universal arm64 + x86_64 build is required.')
    if args.output.exists():
        raise SystemExit(f'Output already exists; choose an empty destination: {args.output}')

    # Collect complete notices before writing any output.
    notices = []
    for name, files in {
        'Defaults': ['license'], 'KeyboardShortcuts': ['license'],
        'LaunchAtLogin-Modern': ['license'], 'Sauce': ['LICENSE'],
        'SwiftHEXColors': ['LICENSE'], 'fuse-swift': ['LICENSE'],
        'swift-log': ['LICENSE.txt', 'NOTICE.txt'],
    }.items():
        for file in files:
            contents = (args.checkouts / name / file).read_text()
            notices.append(f'{name} — {file}\n\n{contents}')

    output = args.output.resolve()
    output.mkdir(parents=True)
    app = output / 'MultiRam.app'
    copy_bundle(source, app)
    notice_text = '\n\n' + ('\n\n' + '=' * 72 + '\n\n').join(notices)
    (app / 'Contents/Resources/ThirdPartyNotices.txt').write_text(notice_text)
    (output / 'ThirdPartyNotices.txt').write_text(notice_text)
    shutil.copy2(ROOT / 'LICENSE', output / 'LICENSE.txt')
    shutil.copy2(ROOT / 'docs/release.md', output / 'Release-Notes.md')

    signing = signing_texts(certificate_name)
    instructions = f'''MultiRam {release_name} — macOS 14+, Intel и Apple Silicon

1. Перетащите MultiRam.app в Applications (Программы).
2. Запустите MultiRam из Applications. Значок появится в строке меню.
3. Option + V открывает историю. Настройки доступны через значок MultiRam.
4. Для автоматической вставки включите MultiRam в «Конфиденциальность и безопасность →
Универсальный доступ» (в macOS 27 — «Управление устройством и доступ к данным»).
Как только доступ включится, MultiRam перезапустится сам.
Если вставка всё равно не работает, завершите MultiRam и откройте его снова.
Если после обновления вставка не работает, а MultiRam уже включён в этом списке:
удалите старую запись кнопкой − и добавьте установленный MultiRam.app из Applications заново.
Разрешения macOS привязаны к подписи сборки и не входят в установщик.
{signing['note']}
Если macOS блокирует запуск: после попытки открыть приложение перейдите в
Системные настройки → Конфиденциальность и безопасность и разрешите открытие MultiRam.
{signing['status']}
Подробнее: https://support.apple.com/en-us/102445

При обновлении сначала завершите ранее запущенное приложение.
Существующая история и настройки сохраняются. Установщик не содержит личной истории.
Раз в сутки MultiRam проверяет на GitHub, вышла ли новая версия (можно выключить в настройках).

English: Drag MultiRam.app to Applications and open it. Use Option + V for history.
Allow Accessibility for automatic pasting; MultiRam restarts by itself once it is on.
{signing['english']}
If blocked, use System Settings → Privacy & Security → Open Anyway after attempting to open it.
'''
    (output / 'Установка.txt').write_text(instructions)

    with tempfile.TemporaryDirectory(prefix='multiram-package-') as temporary:
        temp = Path(temporary)
        # Preserve sandbox permissions, explicitly excluding debugger access.
        entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', source))
        entitlements.pop('com.apple.security.get-task-allow', None)
        entitlements_file = temp / 'entitlements.plist'
        entitlements_file.write_bytes(plistlib.dumps(entitlements))
        timestamp = '--timestamp=none' if adhoc else '--timestamp'
        run('codesign', '--force', '--sign', certificate_sha1 or '-', '--options', 'runtime',
            timestamp, '--entitlements', entitlements_file, app)
        run('codesign', '--verify', '--deep', '--strict', app)
        details = run_stderr('codesign', '-dvv', app)
        requirement = run('codesign', '-d', '-r-', app).decode()
        team = re.search(r'^TeamIdentifier=(.+)$', details, re.M)
        if not adhoc:
            run('codesign', '-d', f'--extract-certificates={temp}/certificate', app)
            if hashlib.sha1((temp / 'certificate0').read_bytes()).hexdigest().upper() != certificate_sha1:
                raise SystemExit(f'The app is not signed by {certificate_name}.')
            # A cdhash requirement would make macOS forget the Accessibility permission on every update.
            if 'certificate leaf' not in requirement or 'cdhash' in requirement:
                raise SystemExit('The designated requirement does not name the signing certificate.')
        final_entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', app))
        if final_entitlements.get('com.apple.security.get-task-allow'):
            raise SystemExit('Release must not grant debugger access.')
        final_executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
        # Resigning changes the Mach-O signature, but never rebuilds the app.
        stage = temp / 'DMG'
        stage.mkdir()
        copy_bundle(app, stage / app.name)
        (stage / 'Applications').symlink_to('/Applications')
        for name in ['Установка.txt', 'LICENSE.txt', 'ThirdPartyNotices.txt', 'Release-Notes.md']:
            shutil.copy2(output / name, stage / name)
        dmg = output / f'MultiRam-{release_name}.dmg'
        run('hdiutil', 'create', '-volname', f'MultiRam {release_name}', '-srcfolder', stage,
            '-format', 'UDZO', '-fs', 'HFS+', dmg)
        run('hdiutil', 'verify', dmg)
        mount = temp / 'Mounted'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, dmg)
        try:
            mounted_app = mount / app.name
            run('codesign', '--verify', '--deep', '--strict', mounted_app)
            mounted_executable = mounted_app / 'Contents/MacOS' / info['CFBundleExecutable']
            if sha256(mounted_executable) != sha256(final_executable):
                raise SystemExit('Mounted app differs from the packaged app.')
            if (mount / 'Applications').readlink() != Path('/Applications'):
                raise SystemExit('The Applications installation shortcut is missing.')
        finally:
            run('hdiutil', 'detach', mount)

        archive = output / f'MultiRam-{release_name}.app.zip'
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
        manifest = {
            'name': 'MultiRam', 'version': info['CFBundleShortVersionString'],
            'build': info['CFBundleVersion'], 'minimum_macos': info['LSMinimumSystemVersion'],
            'architectures': architectures, 'bundle_identifier': info['CFBundleIdentifier'],
            'signing': 'ad hoc' if adhoc else certificate_name,
            'team_identifier': None if adhoc or not team or team.group(1) == 'not set' else team.group(1),
            'notarized': False,
            'source_commit': run('git', '-C', ROOT, 'rev-parse', 'HEAD').decode().strip(),
            'source_has_tracked_changes': bool(run('git', '-C', ROOT, 'status', '--porcelain', '--untracked-files=no')),
            'executable_sha256': sha256(final_executable),
        }
        (output / 'Manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        files = sorted(path for path in output.iterdir() if path.is_file())
        (output / 'SHA256SUMS.txt').write_text(''.join(f'{sha256(path)}  {path.name}\n' for path in files))
    print(f'Release ready: {dmg}')


if __name__ == '__main__':
    main()
