const crypto = require('crypto');
const { execSync } = require('child_process');

try {
    const cert = execSync('keytool -exportcert -alias androiddebugkey -keystore "C:\\Users\\User\\.android\\debug.keystore" -storepass android');
    const base64Hash = crypto.createHash('sha1').update(cert).digest('base64');
    console.log('\n\n========================================');
    console.log('YOUR FACEBOOK KEY HASH:');
    console.log(base64Hash);
    console.log('========================================\n');
} catch (e) {
    console.error('Error generating hash:', e);
}
