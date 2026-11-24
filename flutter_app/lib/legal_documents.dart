import 'package:flutter/material.dart';

class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

class LegalDocument {
  const LegalDocument({required this.title, required this.sections});

  final String title;
  final List<LegalSection> sections;
}

const jengaBizTerms = LegalDocument(
  title: 'Terms of Use',
  sections: [
    LegalSection(
      'About JengaBiz',
      'JengaBiz is provided by MF Technologies to help shopkeepers in Kenya record and review stock, sales activity, and business information. During sign-up, the required agreement records your acceptance of these Terms and the Privacy Policy. Essential on-device storage for sign-in, settings, cached records, and images is described in the Privacy Policy. JengaBiz is a recordkeeping tool, not a bank, payment service, tax adviser, accountant, or legal adviser.',
    ),
    LegalSection(
      'Your account and security',
      'Provide accurate account and shop details, verify your email address, and keep your password, device, and one-time codes private. You are responsible for activity on your account and for limiting access to your shop records. Contact MF Technologies promptly if you believe someone has accessed your account without permission.',
    ),
    LegalSection(
      'Shop records and photos',
      'You are responsible for the accuracy of product names, categories, SKUs, quantities, costs, prices, sales, and other information you enter. You keep your rights to business information and photos you provide. Some accounts may still have one profile photo uploaded before new profile photo uploads were disabled. If present, you can keep it or permanently remove it; it cannot be restored after removal. You must have permission to use each photo and must not upload unlawful content or content that violates another person’s rights. You allow JengaBiz to store and display existing profile and product photos only as needed to provide the service.',
    ),
    LegalSection(
      'Offline use and syncing',
      'The app caches shop data, any existing profile photo, and product images on your phone for faster access and supported offline work. Profile photos uploaded earlier remain in your account until removed; new profile photo uploads are disabled. Product images and supported stock changes sync when a connection returns. Keep the app and its local data intact until pending changes have synced; clearing app data or uninstalling first may permanently remove changes that exist only on that phone.',
    ),
    LegalSection(
      'Reports and business decisions',
      'Stock summaries, revenue totals, sales counts, notifications, and PDF exports use the information in your account. They help with recordkeeping but do not replace your accounting system or professional advice. You remain responsible for business, purchasing, financial, and tax decisions.',
    ),
    LegalSection(
      'Refer & Earn',
      'Refer & Earn is available in Kenya. A new account that enters a valid referral code and verifies its email can award 50 JengaBiz points when the two detected shop locations are in the same county, or 75 points when they are in different counties. Each referred account can qualify once. The app detects location; users cannot choose a county in the referral form. Points are not cash and redemption is not currently available. We may remove points linked to duplicate, fraudulent, or abusive accounts.',
    ),
    LegalSection(
      'Optional device features',
      'Fingerprint or face authentication is handled by your phone’s operating system. Location, contacts, photos, and push notifications depend on device permissions and app settings. Android’s system photo picker shares only the product image you choose; JengaBiz does not browse the full photo or video library. Existing profile photos can be removed from Profile, but new profile photo uploads are disabled. Contacts access is requested only when you choose Invite a contact in Refer & Earn. You can still copy or share your referral link if you decline. You can change permissions or preferences in Android settings; related features may then be unavailable.',
    ),
    LegalSection(
      'Acceptable use and service changes',
      'Use JengaBiz only for lawful business purposes and information you are authorized to manage. Do not disrupt the service, bypass account security, misuse verification codes, or access another user’s records. We may update or discontinue parts of the service. We update the date on the website terms and provide notice in the app or website when a material change needs your attention.',
    ),
    LegalSection(
      'Ending use and support',
      'You may stop using JengaBiz at any time. Contact MF Technologies to request account closure or help with your account data. Some information may need to remain where necessary to protect the service or meet applicable obligations. Nothing in these terms limits rights that cannot be limited by law.',
    ),
    LegalSection(
      'Contact',
      'Email info@mftechnologies.org or call 0748 329 410 or 0712 742 991 for support or questions about these terms.',
    ),
  ],
);

const jengaBizPrivacy = LegalDocument(
  title: 'Privacy Policy',
  sections: [
    LegalSection(
      'Who operates JengaBiz',
      'JengaBiz is operated by MF Technologies. Contact info@mftechnologies.org or call 0748 329 410 or 0712 742 991 for privacy questions and account requests.',
    ),
    LegalSection(
      'Information we use',
      'Account details can include your name, shop name, email address, optional phone number, password hash, account settings, and county recorded for referral eligibility. Some accounts may still contain one profile photo uploaded before profile photo uploads were disabled. You can remove it from Profile; removal is permanent and it cannot be restored. Shop records include products, categories, SKUs or barcodes, quantities, prices, costs, sales activity, and product images. We use this information to provide the app features you request.',
    ),
    LegalSection(
      'Verification and notifications',
      'Email verification uses your email address and a short-lived one-time code. When push notifications are enabled, the app registers a device messaging token and platform so stock alerts can be delivered to that device. You can turn off push alerts in your profile; Android permission settings also apply.',
    ),
    LegalSection(
      'Location and device features',
      'Location permission is optional. If allowed, the app can estimate a nearby supply hub and detect your country and county for Kenya-only referral rules. The referral service receives the detected country and county, not your GPS coordinates. Fingerprint and face checks are performed by Android; JengaBiz receives the authentication result and does not receive or store biometric templates. When you choose a product photo, Android shares only that selected image with JengaBiz through its system photo picker; the app does not browse your photo or video library. Existing profile photos can be removed in the app, and new profile photo uploads are disabled. JengaBiz does not currently use videos. Contacts permission is requested only when you choose Invite a contact. The selected contact’s display name can personalize the invite; your address book is not uploaded to JengaBiz or saved by the app.',
    ),
    LegalSection(
      'On-device storage and syncing',
      'The app stores the session credential in Android secure storage and keeps settings, shop data, any existing profile photo, and product image cache on the phone for faster access and supported offline work. Profile photos uploaded earlier remain in your JengaBiz account until removed. New profile photo uploads are disabled. Product images and supported stock changes sync when online; unsynced changes may be lost if app data is cleared, the app is removed, or the phone is lost first.',
    ),
    LegalSection(
      'Service providers',
      'MF Technologies uses providers for email verification, push notifications, hosting, and network security. Verification emails are sent through Resend and push notifications use Firebase Cloud Messaging. Providers receive information needed to provide those services and may process it in other countries depending on their infrastructure. The JengaBiz website does not use advertising or analytics trackers.',
    ),
    LegalSection(
      'Retention and requests',
      'Account and shop information is kept while needed to provide JengaBiz and maintain your account, or for other applicable service and legal needs. Verification codes expire after a short period and are not retained as active credentials after use or expiry. Email info@mftechnologies.org from the address linked to your account to request account closure, access, correction, or help removing information. We may verify your identity before acting.',
    ),
    LegalSection(
      'Your privacy rights',
      'You may ask how your information is used, request access, object to processing, request correction of false or misleading information, or request deletion of false or misleading information. Other rights may apply under laws that protect you. Contact MF Technologies to submit a request. In Kenya, information about data subject rights is available from the Office of the Data Protection Commissioner (ODPC).',
    ),
    LegalSection(
      'Security and updates',
      'We use reasonable safeguards, including encrypted connections for public services, password hashing, restricted account access, and Android secure storage for session credentials. No online service or device can be guaranteed completely secure. Use a device lock and do not share passwords or verification codes. We update this policy when our information practices change.',
    ),
  ],
);

Future<void> showLegalDocument(BuildContext context, LegalDocument document) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .9,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    document.title,
                    style:
                        Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFF17162A),
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
              itemCount: document.sections.length,
              itemBuilder: (context, index) {
                final section = document.sections[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.heading,
                        style: const TextStyle(
                          color: Color(0xFF17162A),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        section.body,
                        style: const TextStyle(
                          color: Color(0xFF777487),
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
