# Getting Started

You can install Logr either as a versioned **Unlocked Package** or by deploying the source directly from the repository.

## 1. Install into Your Org

::: code-group

```bash [Unlocked Package (Recommended)]
sf package install --package 04tg7000000ZCRJAA4 --wait 10 --target-org <org-alias>
```

```bash [Deploy from Source]
git clone https://github.com/nithesh1992/Logr.git
cd Logr
sf project deploy start --source-dir force-app/main/default/Logr --target-org <org-alias>
```

:::

Or install directly in the browser:

- **Production / Developer Edition**: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tg7000000ZCRJAA4`
- **Sandbox / Scratch Org**: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tg7000000ZCRJAA4`

## 2. Assign Permission Sets

Logr includes two permission sets so you can separate log consumers from users who only generate logs during transactions:

| Permission Set | API Name     | Intended Audience                                                                                                                                                              |
| :------------- | :----------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Logr Admin** | `Logr_Admin` | Developers, admins, and support engineers. Grants full read/edit/delete access to `Logr_Entry__c`, the **Log Entries** tab, list views, reports, and dashboard.                |
| **Logr User**  | `Logr_User`  | End users, integration users, and service accounts. Grants access to `Logr.saveClientLog` so LWC components and Flows can write logs without exposing the `Logr_Entry__c` tab. |

```bash
# For admins and developers
sf org assign permset --name Logr_Admin --target-org <org-alias>

# For standard end users
sf org assign permset --name Logr_User --target-org <org-alias>
```

## 3. Configure Org Defaults (Optional)

Logr works immediately after installation with sensible defaults (`Enabled = true`, `Level = INFO`, `Save Mode = EVENT`, `Flush Debug On Error = true`, `Mask Data = true`, `Retention Days = 30`).

To customize behavior for the entire org, a specific Profile, or a single User while debugging:

1. Open **Setup** and search for **Custom Settings**.
2. Click **Manage** next to **Logr Config** (`Logr_Config__c`).
3. Click **New** at the top for Org-Wide Defaults, or **New** at the bottom to add a Profile or User override.

::: tip Zero-Deploy Production Debugging
Because `Logr_Config__c` is a Hierarchy Custom Setting, you can keep your org-wide level at `WARN` or `INFO` and add a `FINE` override for a single user experiencing an issue. Every `FINE` and `DEBUG` step will be captured for that user alone without redeploying code.
:::

## 4. Verify Your Installation

Run this snippet in Anonymous Apex (`sf apex run --target-org <org-alias>`) or open the **Log Entries** tab in Lightning Experience:

```apex
Logr.start('Installation Check')
    .source('VerifyInstall')
    .tag('Setup')
    .info('Logr is installed and active', new Map<String, Object>{ 'version' => '1.1.0' })
    .save();
```

Open the **Log Entries** tab and switch to the **Today's Logs** list view to inspect the generated record, including its formatted execution trace and Governor Limits snapshot.
