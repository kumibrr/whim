#!/usr/bin/env python3
"""Validate the built app/extension contract, including simulated signing entitlements."""
import json
import plistlib
import sys
from pathlib import Path

build = Path(sys.argv[1]) / 'Build'
products = build / 'Products'
intermediates = build / 'Intermediates.noindex/whim.build'
iphone = products / 'Debug-iphonesimulator/whim.app'
watch = iphone / 'Watch/WhimWatch.app'

def plist(path):
    with path.open('rb') as stream:
        return plistlib.load(stream)

for target, platform, bundle, suffix, group in [
    ('whim', 'iphonesimulator', iphone, 'app', 'group.app.whim.shared'),
    ('WhimLiveActivity', 'iphonesimulator', iphone / 'PlugIns/WhimLiveActivity.appex', 'appex', 'group.app.whim.shared'),
    ('WhimWatch', 'watchsimulator', watch, 'app', 'group.app.whim.watch.shared'),
    ('WhimComplication', 'watchsimulator', watch / 'PlugIns/WhimComplication.appex', 'appex', 'group.app.whim.watch.shared'),
]:
    info = plist(bundle / 'Info.plist')
    assert info.get('CFBundleVersion'), f'{target}: missing build version'
    signing = plist(intermediates / f'Debug-{platform}/{target}.build/{target}.{suffix}-Simulated.xcent')
    assert signing.get('com.apple.security.application-groups') == [group], f'{target}: incorrect App Group'
    privacy = plist(bundle / 'PrivacyInfo.xcprivacy')
    reasons = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons'] for entry in privacy['NSPrivacyAccessedAPITypes']}
    assert '1C8F.1' in reasons.get('NSPrivacyAccessedAPICategoryUserDefaults', []), f'{target}: missing App Group privacy reason'
    assert privacy['NSPrivacyTracking'] is False, f'{target}: tracking must be disabled'
    if suffix == 'appex':
        assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', target
        assert info['CFBundleVersion'] == plist(bundle.parent.parent / 'Info.plist')['CFBundleVersion'], target

assert plist(iphone / 'Info.plist')['NSSupportsLiveActivities'] is True
assert 'processing' in plist(iphone / 'Info.plist').get('UIBackgroundModes', []), 'iPhone: background maintenance is not enabled'
assert plist(iphone / 'Info.plist').get('BGTaskSchedulerPermittedIdentifiers') == ['app.whim.maintenance'], 'iPhone: maintenance identifier is not permitted'
for bundle in [iphone, watch]:
    assert 'audio' in plist(bundle / 'Info.plist').get('UIBackgroundModes', []), f'{bundle.name}: background audio recording is not enabled'
    metadata = json.loads((bundle / 'Metadata.appintents/extract.actionsdata').read_text())
    actions = metadata['actions']
    for name, title in [('RecordWhimIntent', 'Record a Whim'), ('StopWhimRecordingIntent', 'Stop Whim Recording')]:
        assert actions[name]['title']['key'] == title
        assert 'com.apple.link.systemProtocol.AudioRecording' in actions[name]['systemProtocols']
        shortcuts = [item for item in metadata['autoShortcuts'] if item['actionIdentifier'] == name]
        assert len(shortcuts) == 1, f'{bundle.name}: missing or duplicate {title}'
        assert shortcuts[0]['shortTitle']['key'] == title
        assert shortcuts[0]['phraseTemplates'][0]['key'] == title + ' in ${applicationName}'
    assert actions['StopWhimRecordingIntent']['openAppWhenRun'] is False, 'Stop must not launch recording-first UI'
    if bundle == iphone:
        assert actions['RecordWhimIntent']['authenticationPolicy'] == 0, 'Record must permit locked execution'
        assert actions['RecordWhimIntent']['openAppWhenRun'] is False
        assert actions['StopWhimRecordingIntent']['openAppWhenRun'] is False

print('Built system surfaces: four App Groups, extension embedding, Live Activity support, and recording shortcuts verified.')
