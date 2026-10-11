import com.android.apksig.ApkVerifier;
import com.android.apksig.SigningCertificateLineage;
import java.io.File;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.HexFormat;

/** Reads and cryptographically verifies the lineage embedded in the actual APK. */
public class VerifyAndroidLineage {
    static String sha(X509Certificate c) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(c.getEncoded()));
    }
    public static void main(String[] args) throws Exception {
        File apk = new File(args[0]);
        String previous = args[1], current = args[2];
        SigningCertificateLineage lineage = SigningCertificateLineage.readFromApkFile(apk);
        var certificates = lineage.getCertificatesInLineage();
        boolean valid = certificates.size() == 2 && sha(certificates.get(0)).equals(previous)
            && sha(certificates.get(1)).equals(current);
        var capability = lineage.getSignerCapabilities(certificates.get(0));
        valid &= capability.hasInstalledData() && !capability.hasRollback()
            && !capability.hasPermission() && !capability.hasSharedUid() && !capability.hasAuth();
        StringBuilder results = new StringBuilder();
        for (int api : new int[]{28, 32, 33, 36}) {
            var result = new ApkVerifier.Builder(apk).setMinCheckedPlatformVersion(api)
                .setMaxCheckedPlatformVersion(api).build().verify();
            boolean okay = result.isVerified() && result.getSignerCertificates().size() == 1
                && sha(result.getSignerCertificates().get(0)).equals(current);
            valid &= okay;
            if (!results.isEmpty()) results.append(',');
            results.append("{\"api\":").append(api).append(",\"verified\":").append(okay).append('}');
        }
        System.out.println("{\"passed\":" + valid + ",\"embedded_lineage_verified\":true,"
            + "\"legacy_certificate_sha256\":\"" + sha(certificates.get(0)) + "\","
            + "\"release_certificate_sha256\":\"" + sha(certificates.get(1)) + "\","
            + "\"installed_data\":" + capability.hasInstalledData() + ",\"rollback\":"
            + capability.hasRollback() + ",\"platform_checks\":[" + results + "]}");
        if (!valid) System.exit(1);
    }
}
