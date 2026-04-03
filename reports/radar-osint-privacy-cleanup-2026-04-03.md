# Radar: OSINT Tools for Personal Privacy Cleanup

**Date:** 2026-04-03
**Category:** personal-privacy
**Type:** radar-research
**Scope:** Personal project -- not Shikki development

---

## TL;DR

Use OSINT tools offensively on yourself to find your own digital footprint, then systematically remove it. The pipeline is: **Audit -> Find -> Remove -> Monitor**. Start with HaveIBeenPwned and holehe for email exposure, then Sherlock/Maigret for username enumeration, then manually delete or use professional services for data broker removal.

---

## 1. Tools Researched

### 1.1 Username Search Tools

#### Sherlock -- The Gold Standard
- **Repo:** https://github.com/sherlock-project/sherlock
- **Stars:** 77,948 | **Language:** Python | **Status:** Actively maintained
- **What it does:** Hunts down social media accounts by username across 400+ social networks. The most popular and battle-tested username OSINT tool.
- **Install:** `pipx install sherlock-project` or `brew install sherlock`
- **Usage:**
  ```bash
  sherlock yourusername
  sherlock user1 user2 user3  # multi-user
  sherlock yourusername --csv  # export CSV
  sherlock yourusername --xlsx  # export Excel
  ```
- **Privacy cleanup relevance:** HIGH. Run with your known usernames to discover forgotten accounts. Outputs a list of confirmed profiles with URLs for manual deletion. Supports Tor routing (`--tor`) if you want to avoid alerting rate limiters.

#### Maigret -- Sherlock on Steroids
- **Repo:** https://github.com/soxoj/maigret
- **Stars:** 19,339 | **Language:** Python | **Status:** Actively maintained
- **What it does:** Fork of Sherlock expanded to 3000+ sites. Goes further by parsing profile pages and extracting personal info, links to other profiles, and performing recursive search by newly found usernames/IDs.
- **Install:** `pip3 install maigret`
- **Usage:**
  ```bash
  maigret yourusername
  maigret yourusername --reports-dir ./reports  # save HTML/PDF/JSON reports
  maigret yourusername -a  # use all 3000+ sites (slower)
  maigret yourusername --tags us  # filter by country
  ```
- **Privacy cleanup relevance:** VERY HIGH. Best for deep discovery. Extracts profile metadata (bio, avatar, links) and chains searches recursively. The HTML report is a visual map of your digital footprint. Also available as a Telegram bot (@maigret_search_bot) if you don't want to install.

#### Blackbird -- Username + Email Dual Search
- **Repo:** https://github.com/p1ngul1n0/blackbird
- **Stars:** 5,907 | **Language:** Python | **Status:** Actively maintained
- **What it does:** OSINT tool that searches both username AND email across 600+ platforms (via WhatsMyName integration). Includes free AI-powered profiling that analyzes where accounts are found and generates a behavioral profile.
- **Install:**
  ```bash
  git clone https://github.com/p1ngul1n0/blackbird && cd blackbird
  pip install -r requirements.txt
  ```
- **Usage:**
  ```bash
  python blackbird.py --username yourusername
  python blackbird.py --email you@example.com
  python blackbird.py --username yourusername --ai  # AI profiling
  python blackbird.py --email you@example.com --pdf  # export PDF
  ```
- **Privacy cleanup relevance:** HIGH. The email search is the differentiator -- most tools only search by username. The AI profiling gives a third-party perspective on what your digital presence reveals. PDF export is useful for documentation.

#### Social Analyzer -- The Industrial Scanner
- **Repo:** https://github.com/qeeqbox/social-analyzer
- **Stars:** 22,457 | **Language:** JavaScript/Python | **License:** AGPL-3.0 | **Status:** Actively maintained
- **What it does:** API, CLI, and Web App for finding profiles across 1000+ social media sites. Uses a multi-layer detection system with confidence rating (0-100). Supports OCR, screenshots, metadata extraction, and force-directed graph visualization.
- **Install (Python):** `pip3 install social-analyzer`
- **Install (Node):** `npm install && npm start` (web UI at http://0.0.0.0:9005)
- **Usage:**
  ```bash
  python3 -m social-analyzer --username "yourusername"
  python3 -m social-analyzer --username "yourusername" --metadata --top 100
  python3 -m social-analyzer --username "yourusername" --filter "good"  # high-confidence only
  ```
- **Privacy cleanup relevance:** HIGH. The confidence rating (good/maybe/bad) helps filter false positives. The web UI with screenshots is useful for visual verification. Special detection for Facebook (phone/name), Gmail, and Google accounts.

### 1.2 Email Exposure Tools

#### holehe -- Email to Registered Accounts
- **Repo:** https://github.com/megadose/holehe
- **Stars:** 10,569 | **Language:** Python | **Status:** Actively maintained
- **What it does:** Checks if an email is attached to an account on 120+ sites by exploiting the "forgot password" function. Does NOT alert the target email (silent check). Returns the site name, whether the account exists, and partial email recovery info.
- **Install:** `pip3 install holehe`
- **Usage:**
  ```bash
  holehe you@example.com
  ```
- **Privacy cleanup relevance:** CRITICAL. This is the #1 tool for discovering where your email is registered. Run it against every email address you own/have ever used. The output tells you exactly which services have your email, so you can go delete those accounts.

#### h8mail -- Breach Hunting for Your Own Emails
- **Repo:** https://github.com/khast3x/h8mail
- **Stars:** 4,937 | **Language:** Python | **Status:** Maintained
- **What it does:** Email OSINT and password breach hunting tool. Queries multiple breach databases (HaveIBeenPwned, Snusbase, DeHashed, IntelX, etc.) and local breach compilations to find exposed credentials associated with your email.
- **Install:** `pip3 install h8mail`
- **Usage:**
  ```bash
  h8mail -t you@example.com
  h8mail -t you@example.com -o results.csv
  h8mail -t targets.txt  # bulk file
  h8mail -t you@example.com -k "hibp=YOUR_API_KEY"  # with HIBP API
  h8mail -t you@example.com --chase  # find and chase related emails
  ```
- **Privacy cleanup relevance:** CRITICAL. Tells you which breaches your email appeared in, and what data was exposed (password hashes, plaintext passwords, IPs, usernames). The `--chase` feature finds related emails automatically. Use with HaveIBeenPwned API key for best results.

### 1.3 Curated Reference Lists

#### awesome-osint
- **Repo:** https://github.com/jivoi/awesome-osint
- **Stars:** 25,603 | **Status:** Actively maintained
- **What it does:** Curated list of OSINT tools and resources, organized by category. Covers everything from search engines and social media tools to data breach engines, people investigation, email search, and privacy/encryption tools.
- **Key sections for privacy cleanup:**
  - Username Check -- 20+ tools including Sherlock, Maigret, Blackbird
  - Email Search / Email Check -- 30+ tools including holehe, h8mail, HIBP, Hunter.io
  - People Investigations -- 30+ services for finding public records
  - Data Breach Search Engines -- CredenShow, HEROIC.NOW, Venacus, StealSeek
  - Privacy and Encryption Tools -- justdeleteme, Abine, privacy.com
- **Privacy cleanup relevance:** REFERENCE. Use as a master index when the primary tools don't find everything.

#### osint_stuff_tool_collection
- **Repo:** https://github.com/cipher387/osint_stuff_tool_collection
- **Stars:** 7,727 | **Status:** Actively maintained (since 2021)
- **What it does:** 1000+ online tools for OSINT organized by category. Covers social media (per-platform), email, nicknames, passwords, messengers, domain/IP, and more. Many are web-based tools requiring no installation.
- **Key sections for privacy cleanup:**
  - Emails -- dedicated section with verification and lookup tools
  - Nicknames -- username search across platforms
  - Passwords -- breach and leak databases
  - Social Media -- platform-specific tools (per-site subsections)
  - Universal Contact Search and Leaks Search
- **Privacy cleanup relevance:** REFERENCE. Broader than awesome-osint, includes more niche and web-based tools. Good for when you need platform-specific lookups.

---

## 2. Data Breach Checking

### HaveIBeenPwned (HIBP)
- **URL:** https://haveibeenpwned.com
- **What:** The standard for breach checking. Search by email or phone number. Shows which breaches your data appeared in, what data types were exposed, and when.
- **API:** Available for $3.50/month (HIBP API key). Needed for h8mail integration.
- **Action:** Check every email you have ever used. Subscribe to notifications for future breaches.

### Other Breach Search Engines
| Service | URL | Notes |
|---------|-----|-------|
| DeHashed | https://dehashed.com | Paid. Searches breaches by email, username, IP, name, phone, address, VIN |
| LeakCheck | https://leakcheck.io | 7.5B+ entries from 3000+ databases. Search by email, username, keyword, password |
| IntelX | https://intelx.io | Free trial. Searches dark web, paste sites, breach data |
| CredenShow | https://credenshow.com | Identify compromised credentials |
| HEROIC.NOW | https://heroic.com | Free dark web scan for leaked data |
| StealSeek | https://stealseek.io | Breach analysis engine |
| Venacus | https://venacus.com | Breach search with notification alerts |

---

## 3. GitHub Commit Email Exposure

### The Problem
Every Git commit contains an author email in its metadata. If you push commits with your personal email, it is permanently embedded in the repository history and visible to anyone who clones the repo.

```bash
# Check what email is exposed in your commits
git log --format='%ae' | sort -u
```

### Prevention (Going Forward)

**Step 1: Enable GitHub noreply email**
1. Go to GitHub Settings > Emails
2. Check "Keep my email addresses private"
3. Check "Block command line pushes that expose my email"
4. Note your noreply address: `YOUR_ID+username@users.noreply.github.com`

**Step 2: Configure Git globally**
```bash
git config --global user.email "YOUR_ID+username@users.noreply.github.com"
```

**Step 3: Verify**
```bash
git config --global user.email  # should show noreply address
```

### Cleanup (Rewriting History)

> WARNING: Rewriting history is destructive. It changes commit hashes and requires force-pushing. Only do this for repos you own. Collaborators will need to re-clone.

#### Option A: git-filter-repo (Recommended)
```bash
# Install
pip3 install git-filter-repo

# Rewrite all commits replacing old email with noreply
git filter-repo --email-callback '
    return email.replace(b"real@email.com", b"ID+user@users.noreply.github.com")
'

# Force push (you own the repo)
git push --force --all
git push --force --tags
```

#### Option B: BFG Repo-Cleaner (12k stars)
- **Repo:** https://github.com/rtyley/bfg-repo-cleaner
- Primarily for removing large files/secrets, but can be adapted for email cleanup
- Faster than `git filter-branch` but `git-filter-repo` is now the recommended replacement

#### Option C: GitHub Support
For repos you don't own, contact GitHub Support to request removal of cached personal data. GitHub can also purge your email from their event archives.

### Quick Audit Script
```bash
#!/bin/bash
# Find all repos exposing your personal email
# Run from your workspace root
for repo in $(find . -name ".git" -type d -maxdepth 3); do
    dir=$(dirname "$repo")
    exposed=$(git -C "$dir" log --format='%ae' 2>/dev/null | grep -i "your-real-email@" | head -1)
    if [ -n "$exposed" ]; then
        echo "EXPOSED: $dir ($exposed)"
    fi
done
```

---

## 4. Data Broker Removal

### What Are Data Brokers?
Companies that collect and sell your personal information (name, address, phone, email, employment, family) scraped from public records, social media, purchase history, and other sources.

### Manual Removal (Free, Time-Consuming)
1. **Google yourself** -- `"Your Full Name" + city` or `"your@email.com"`
2. **Opt out from major brokers** (each has its own process):

| Broker | Opt-out URL | Difficulty |
|--------|------------|------------|
| Spokeo | spokeo.com/optout | Easy |
| BeenVerified | beenverified.com/faq/opt-out | Medium |
| WhitePages | whitepages.com/suppression-requests | Medium |
| Intelius | intelius.com/opt-out | Medium |
| PeopleFinder | peoplefinder.com/optout | Easy |
| Radaris | radaris.com/control/privacy | Medium |
| TruePeopleSearch | truepeoplesearch.com/removal | Easy |
| FastPeopleSearch | fastpeoplesearch.com/removal | Easy |
| ThatsThem | thatsthem.com/optout | Easy |
| USPhoneBook | usphonebook.com/opt-out | Easy |

3. **Use justdeleteme** (https://justdelete.me / https://github.com/jdm-contrib/jdm, 1.2k stars) -- directory of direct links to delete your account from web services, color-coded by difficulty (easy/medium/hard/impossible).

### Professional Services (Paid, Automated)

| Service | Price | What They Do |
|---------|-------|-------------|
| **DeleteMe** | $129/year | Scans 750+ data brokers, submits opt-outs on your behalf, re-checks quarterly. US-focused. Reports every 3 months. |
| **Incogni** (Surfshark) | $77/year ($6.49/mo) | Automated data broker removal across 180+ brokers. EU GDPR + US CCPA leverage. Monthly progress reports. |
| **Optery** | $249/year (premium) | 270+ data brokers, automatic re-removal, exposure scoring. Free tier scans but doesn't remove. |
| **Privacy Duck** | $500+/year | Manual, human-driven removal. More thorough but expensive. Good for high-profile individuals. |
| **Kanary** | $89/year | Data broker removal + dark web monitoring. |
| **Abine Blur** | $39/year | Masked emails, masked phone numbers, masked credit cards + tracker blocking. Prevention-focused rather than cleanup. |

**Recommendation:** Start with Incogni (cheapest, solid coverage) or DeleteMe (most established). Both handle the tedious broker-by-broker opt-out process automatically.

---

## 5. Spam Email Source Discovery

### Find Where Your Email Is Exposed

1. **holehe** -- Find which services have your email registered
2. **h8mail** -- Find which breaches exposed your email
3. **HaveIBeenPwned** -- Comprehensive breach database
4. **Google dork:** `"your@email.com"` -- Find public pages listing your email
5. **Hunter.io** -- Reverse email lookup, finds associated domains

### Stop Spam at the Source

1. **Unsubscribe** from everything holehe finds that you don't use
2. **Delete accounts** you no longer need (use justdeleteme for direct links)
3. **Use email aliases going forward:**
   - **Apple Hide My Email** (built into iCloud+)
   - **SimpleLogin** (open source, now owned by Proton)
   - **Firefox Relay** (Mozilla)
   - **Abine Blur** masked emails
   - **Plus addressing:** `you+service@gmail.com` to track who sells your email
4. **Report to spam registries** if a sender won't stop

---

## 6. Action Plan: Step-by-Step

### Phase 1: AUDIT (Day 1 -- 2 hours)

```bash
# 1. Check breach exposure
# Visit https://haveibeenpwned.com and check every email you've ever used
# Subscribe to breach notifications

# 2. Find where your email is registered
pip3 install holehe
holehe your-main@email.com
holehe your-old@email.com
holehe your-work@email.com

# 3. Check GitHub email exposure
git log --format='%ae' | sort -u  # in each repo you own

# 4. Install h8mail for deeper breach hunting
pip3 install h8mail
h8mail -t your-main@email.com -o breach-results.csv
```

### Phase 2: FIND (Day 2 -- 3 hours)

```bash
# 5. Username enumeration (run all your known usernames)
pipx install sherlock-project
sherlock yourusername --csv

# 6. Deep search with Maigret (slower but more thorough)
pip3 install maigret
maigret yourusername --reports-dir ./privacy-audit

# 7. Combined username + email search
git clone https://github.com/p1ngul1n0/blackbird && cd blackbird
pip install -r requirements.txt
python blackbird.py --username yourusername --pdf
python blackbird.py --email your@email.com --pdf

# 8. Google yourself
# Search: "Your Full Name" + city
# Search: "your@email.com"
# Search: "yourusername"
# Check Google Images for your face
```

### Phase 3: REMOVE (Days 3-7 -- ongoing)

1. **Change passwords** for any account found in breaches (use a password manager)
2. **Enable 2FA** on all remaining accounts
3. **Delete unused accounts** found by Sherlock/Maigret/holehe
   - Use https://justdelete.me for direct deletion links
   - Screenshot each deletion confirmation
4. **Fix GitHub email exposure:**
   ```bash
   git config --global user.email "ID+user@users.noreply.github.com"
   ```
   - For owned repos with exposed emails, use `git-filter-repo` to rewrite
5. **Opt out of data brokers** manually (see table above) or sign up for DeleteMe/Incogni
6. **Request Google to remove** outdated/sensitive search results:
   - https://support.google.com/websearch/troubleshooter/9685456

### Phase 4: MONITOR (Ongoing)

1. **HaveIBeenPwned notifications** -- already subscribed in Phase 1
2. **Google Alerts** -- set up alert for `"Your Full Name"` and `"your@email.com"`
3. **Re-run scans quarterly:**
   ```bash
   holehe your@email.com  # check for new registrations
   sherlock yourusername   # check for impersonation
   ```
4. **Use email aliases** for all new signups (SimpleLogin, Apple Hide My Email)
5. **DeleteMe/Incogni** re-checks automatically if subscribed

---

## 7. Tool Comparison Matrix

| Tool | Type | Stars | Sites | Input | Output | Best For |
|------|------|-------|-------|-------|--------|----------|
| Sherlock | Username search | 78k | 400+ | Username | TXT/CSV/XLSX | Quick username audit |
| Maigret | Username search | 19k | 3000+ | Username | HTML/PDF/JSON | Deep profile discovery |
| Blackbird | Username + email | 6k | 600+ | Username/Email | PDF/CSV | Dual search, AI profiling |
| social-analyzer | Username search | 22k | 1000+ | Username | Web UI/JSON | Visual verification |
| holehe | Email lookup | 10.5k | 120+ | Email | CLI | Finding registered accounts |
| h8mail | Breach hunting | 5k | N/A | Email | CSV/JSON | Finding breached credentials |
| HaveIBeenPwned | Breach check | N/A | N/A | Email/Phone | Web | Breach notifications |

---

## 8. Recommended Execution Order

1. **holehe** -- Run first, fastest, tells you where your email lives
2. **HaveIBeenPwned** -- Check breaches, subscribe to alerts
3. **Sherlock** -- Quick username scan across 400 sites
4. **h8mail** -- Deep breach hunting with API keys
5. **Maigret** -- Thorough 3000-site scan with profile parsing
6. **Blackbird** -- Supplementary email+username combined search
7. **justdeleteme** -- Use the results to delete accounts
8. **GitHub email fix** -- Configure noreply, rewrite history if needed
9. **Data broker opt-out** -- Manual or via DeleteMe/Incogni
10. **Set up monitoring** -- Google Alerts, HIBP notifications, quarterly re-scans

---

## 9. Budget Recommendations

### Free Tier (DIY)
- All CLI tools listed above are free and open source
- Manual data broker opt-outs are free but time-consuming (expect 10-20 hours)
- HaveIBeenPwned web search is free

### Minimal Spend (~$100/year)
- **Incogni** at $77/year for automated data broker removal
- **HaveIBeenPwned API** at $3.50/month for h8mail integration
- Total: ~$119/year

### Comprehensive (~$250/year)
- **DeleteMe** at $129/year (or Incogni at $77/year)
- **HaveIBeenPwned API** at $42/year
- **SimpleLogin Premium** at $30/year for email aliases
- Total: ~$150-$200/year

---

## 10. EU/France-Specific Notes (GDPR)

As an EU resident, you have additional rights under GDPR:
- **Right to erasure (Article 17)** -- request any company delete your data
- **Right of access (Article 15)** -- request a copy of all data they hold on you
- **Right to be forgotten** -- request search engines delist results about you

Template email for GDPR data deletion request:
```
Subject: GDPR Data Deletion Request - Article 17

I am writing to request the erasure of all personal data you hold
relating to me, as is my right under Article 17 of the General Data
Protection Regulation (EU 2016/679).

My identifying information:
- Name: [Your Name]
- Email: [your@email.com]
- Account/Username: [if applicable]

Please confirm deletion within 30 days as required by Article 12(3).

Regards,
[Your Name]
```

Services like Incogni specifically leverage GDPR/CCPA for their removal requests, which makes them more effective for EU residents.

---

*Report generated 2026-04-03. Tools and star counts current as of research date.*
