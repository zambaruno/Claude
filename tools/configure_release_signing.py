"""Configure release signing in the generated Kotlin Gradle project.

Credentials come only from CI environment variables and the temporary keystore.
"""
from pathlib import Path
import re

path = Path("android/app/build.gradle.kts")
gradle = path.read_text()
if 'applicationId = "com.zambaruno.lost"' not in gradle:
    raise RuntimeError("Unexpected Android applicationId")
if gradle.count("    buildTypes {") != 1:
    raise RuntimeError("Unexpected generated Gradle buildTypes block")
if gradle.count('signingConfig = signingConfigs.getByName("debug")') != 1:
    raise RuntimeError("Unexpected generated Gradle debug signing configuration")
signing = '''    signingConfigs {
        create("release") {
            keyAlias = System.getenv("LOST_UPLOAD_KEY_ALIAS") ?: error("Missing upload key alias")
            keyPassword = System.getenv("LOST_UPLOAD_KEY_PASSWORD") ?: error("Missing upload key password")
            storeFile = file(System.getenv("LOST_UPLOAD_KEYSTORE_PATH") ?: error("Missing upload keystore path"))
            storePassword = System.getenv("LOST_UPLOAD_STORE_PASSWORD") ?: error("Missing upload store password")
        }
    }
'''
gradle = gradle.replace("    buildTypes {", signing + "    buildTypes {", 1)
gradle = gradle.replace('signingConfig = signingConfigs.getByName("debug")',
                        'signingConfig = signingConfigs.getByName("release")', 1)
path.write_text(gradle)
