"""Apply Android permissions and Magic Link callback after flutter create."""
from pathlib import Path
import xml.etree.ElementTree as ET

# The Play application ID must stay fixed across every generated build.
gradle = Path('android/app/build.gradle.kts').read_text()
if 'namespace = "com.zambaruno.lost"' not in gradle or 'applicationId = "com.zambaruno.lost"' not in gradle:
    raise RuntimeError('Expected Android namespace and applicationId com.zambaruno.lost')
main_activity = Path('android/app/src/main/kotlin/com/zambaruno/lost/MainActivity.kt')
if not main_activity.is_file() or 'package com.zambaruno.lost' not in main_activity.read_text():
    raise RuntimeError('MainActivity package does not match com.zambaruno.lost')

path = Path('android/app/src/main/AndroidManifest.xml')
ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ns)
tree = ET.parse(path)
root = tree.getroot()
application = root.find('application')
if application is None:
    raise RuntimeError('Flutter Android application was not generated')
application.set(f'{{{ns}}}label', 'LOST')
for permission in ('android.permission.INTERNET', 'android.permission.CAMERA',
                   'android.permission.ACCESS_FINE_LOCATION',
                   'android.permission.ACCESS_COARSE_LOCATION'):
    if not any(e.get(f'{{{ns}}}name') == permission for e in root.findall('uses-permission')):
        ET.SubElement(root, 'uses-permission', {f'{{{ns}}}name': permission})
activity = root.find('./application/activity')
if activity is None:
    raise RuntimeError('Flutter Android activity was not generated')
# Supabase Flutter handles the auth callback through app_links. Flutter's own
# route handler would also consume it and can leave the login screen open.
if not any(e.get(f'{{{ns}}}name') == 'flutter_deeplinking_enabled' for e in activity.findall('meta-data')):
    ET.SubElement(activity, 'meta-data', {f'{{{ns}}}name': 'flutter_deeplinking_enabled',
                                          f'{{{ns}}}value': 'false'})
callback = ET.SubElement(activity, 'intent-filter')
ET.SubElement(callback, 'action', {f'{{{ns}}}name': 'android.intent.action.VIEW'})
ET.SubElement(callback, 'category', {f'{{{ns}}}name': 'android.intent.category.DEFAULT'})
ET.SubElement(callback, 'category', {f'{{{ns}}}name': 'android.intent.category.BROWSABLE'})
ET.SubElement(callback, 'data', {f'{{{ns}}}scheme': 'com.zambaruno.lost',
                                 f'{{{ns}}}host': 'login-callback'})
tree.write(path, encoding='utf-8', xml_declaration=True)
