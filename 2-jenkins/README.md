# 2. Jenkins: Web Application Build and Continuous Integration

**Goal:** A Jenkins **Freestyle Project** that pulls the Vehicle Rental Management System from GitHub, compiles it, runs tests with Maven (`clean test package`), reports the results and archives `VehicleRentalManagement.war`.

| Setting | Value |
|---------|-------|
| Job name | `VehicleRental-CI` |
| Repository | `https://github.com/nikithamoturi/VehicleRentalManagementSystem.git` (or your fork) |
| Branch | `*/main` |
| Trigger | Poll SCM: `H/5 * * * *` |
| Maven goals | `clean test package` |
| Test reports | `target/surefire-reports/*.xml` |
| Artifact | `target/*.war` → `VehicleRentalManagement.war` |

---

## Before you start (one-time setup)

1. **Jenkins is running.** Open `http://localhost:8080` (or the port your Jenkins uses), unlock it with the initial admin password and install the **suggested plugins**. These include *Git* and *JUnit*.
   - With Docker: `docker run -d --name jenkins -p 8090:8080 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts`. Get the password with `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`.
2. **Configure Maven:** go to **Manage Jenkins → Tools → Maven installations → Add Maven**. Set Name = `Maven3`, tick **Install automatically**, pick the latest 3.9.x and **Save**.
3. **JDK:** the JDK that Jenkins itself runs on (17 or 21) is enough. The project compiles for Java 8, and newer JDKs can do that.

---

## Step 1: Create the Freestyle Project and connect GitHub

1. Dashboard → **New Item** → name `VehicleRental-CI` → choose **Freestyle project** → **OK**.
2. *(Optional)* **General** → tick **GitHub project** and enter the repo URL without `.git`.
3. **Source Code Management** → select **Git**.
   - **Repository URL:** `https://github.com/nikithamoturi/VehicleRentalManagementSystem.git`
   - **Credentials:** `- none -` (public repo). For a private fork, add a GitHub username + Personal Access Token.

## Step 2: Branch and build trigger

- **Branches to build → Branch Specifier:** `*/main`. This is the repo's only branch.
- **Build Triggers** → tick **Poll SCM** → Schedule: `H/5 * * * *`.
  - Jenkins checks GitHub about every 5 minutes and builds only when there is a new commit.
  - **Why polling:** a lab Jenkins on `localhost` can't receive GitHub webhooks, because GitHub can't reach it. If Jenkins has a public URL, pick **"GitHub hook trigger for GITScm polling"** instead. Then add a webhook in GitHub at **Settings → Webhooks** with URL `http://<jenkins-host>:8080/github-webhook/`, which builds immediately on every push.
  - You can always also click **Build Now** for a manual build.

## Step 3: Maven build step

**Build Steps → Add build step → Invoke top-level Maven targets**

- **Maven Version:** `Maven3`
- **Goals:** `clean test package`
  - `clean` deletes the old `target/` folder
  - `test` compiles and runs the unit tests (Surefire)
  - `package` builds `target/VehicleRentalManagement.war`
- On a Windows agent, the same goals work. Alternatively use **Execute Windows batch command** with `mvn clean test package`.

## Step 4: Test reports, run the job and show a failed build

**Post-build Actions → Add post-build action → Publish JUnit test result report**

- **Test report XMLs:** `target/surefire-reports/*.xml`
- Tick **"Do not fail the build on empty test results"**. The original repo has **no test classes**, so without this the build would be marked failed.

Click **Save** → **Build Now**.

- Open build **#1 → Console Output** and look for:
  - `Cloning the remote Git repository` / `Checking out Revision ... (refs/remotes/origin/main)`
  - `[INFO] --- surefire:3.3.0:test` → `No tests to run.` (or `Tests run: 3, Failures: 0` if you added the sample test)
  - `[INFO] Building war: .../target/VehicleRentalManagement.war`
  - `[INFO] BUILD SUCCESS` → `Finished: SUCCESS` (green ✔)
- **Test results:** on the build page, click **Test Result**. The job page also gets a **Test Result Trend** graph after two builds.

### Getting real test results (recommended)

1. **Fork** the repo on GitHub and point the job's Repository URL at your fork.
2. Add [`WebappPagesTest.java`](WebappPagesTest.java) to the fork at
   `src/test/java/com/kmit/vehiclerental/WebappPagesTest.java`.
   JUnit 4.13.1 is already in the `pom.xml`, so no changes are needed there.
3. Commit. Poll SCM picks it up, or click **Build Now**. You'll see `Tests run: 3, Failures: 0, Errors: 0`.

### Demonstrating a FAILED build (pick any one)

| Method | What to do | What Jenkins shows |
|--------|-----------|--------------------|
| **Failing test** (best) | In your fork, change the expected text in `homePageHasTitle()` to `"Vehicle Booking Portal"` and commit | `Tests run: 3, Failures: 1`, `BUILD FAILURE`, `Finished: FAILURE`, red ✘. **Test Result** names the failed test and the message `Home page title changed` |
| **Compilation error** | Add a Java file with a syntax error (e.g. a missing `;`) | `COMPILATION ERROR` with file and line number, `Finished: FAILURE` |
| **Wrong goal** | Change Goals to `clean tset package` | `Unknown lifecycle phase "tset"`, `Finished: FAILURE` |
| **Wrong branch** | Branch Specifier `*/develop` | `ERROR: Couldn't find any revision to build`, `Finished: FAILURE` |

After the demo, **revert the change** and build again. The build goes back to green (Jenkins reports it as *"Back to normal"*).

## Step 5: Archive the WAR file

**Post-build Actions → Add post-build action → Archive the artifacts**

- **Files to archive:** `target/*.war`
- Click **Advanced** and tick **"Archive artifacts only if build is successful"**. Optionally also tick **Fingerprint all archived artifacts**.

Make sure *Publish JUnit test result report* comes before *Archive the artifacts* (drag the handles if needed). Click **Save**, then **Build Now**.

**Verify:** open the build page (e.g. `#3`). Under **Build Artifacts** you'll see **`VehicleRentalManagement.war`**, which you can click to download. The job's main page also shows **Last Successful Artifacts**. The console ends with `Archiving artifacts` → `Finished: SUCCESS`.

---

## Scenario-based Questions

**Q1. How would Jenkins help developers detect an error introduced while changing the vehicle booking process?**
Every commit to the booking code automatically triggers a build: Poll SCM or a webhook notices the change, and Jenkins runs `clean test package`. If the change breaks compilation or makes a booking test fail, the build turns **red (FAILURE)** within minutes. The **console output** shows the exact compiler error or failing test, and the **Test Result** page shows which test failed with its assertion message. The **Changes** section lists the commit and author that caused it. Jenkins can also email or Slack the team. The bug is caught right after the commit, while the change is fresh, instead of during manual testing or by customers in production.

**Q2. What should the team check when a Maven build fails because a dependency cannot be resolved?**
The console shows something like `Could not resolve dependencies` or `Could not transfer artifact`. Check:
- the **groupId / artifactId / version** in `pom.xml` for typos, and whether that version actually exists in Maven Central
- **network access** from the Jenkins machine to `repo.maven.apache.org`, plus proxy or firewall settings (proxy in `~/.m2/settings.xml`)
- for private or company artifacts, that the **repository URL and credentials** are configured in `settings.xml` or the pom
- a **corrupted local cache**: delete the artifact's folder in `~/.m2/repository`, or build with `mvn -U clean test package` to force updates
- that the **Maven/JDK versions** configured in Jenkins are compatible with the plugins and dependencies
- whether the build works locally with the same command, to tell a code problem from a Jenkins environment problem

**Q3. Why should test execution be included in the automated build of a rental application?**
A successful compile only proves the code is syntactically valid, not that it behaves correctly. Running tests on every build checks business logic automatically: rental price calculation, date and availability checks, booking validation. It catches **regressions** where a new change breaks an existing feature. A failing test stops the pipeline, so a broken WAR is never produced or deployed. That protects customers from wrong bookings or charges. The JUnit reports and trend graph also give the team a visible record of quality over time.

**Q4. How can the Freestyle Project be restricted to build a feature branch instead of the main branch?**
In **Configure → Source Code Management → Git → Branches to build**, change the **Branch Specifier** from `*/main` to the feature branch, e.g. `*/feature/online-booking` (or `refs/heads/feature/online-booking`). Jenkins then checks out, polls and builds only that branch, and commits to `main` no longer trigger this job. A common practice is to create a separate job for each important branch, e.g. `VehicleRental-CI-feature`. Building many branches automatically is better handled by a Multibranch Pipeline.

**Q5. What is the benefit of archiving the WAR file for each successful Jenkins build?**
- **Traceability:** each WAR is tied to a build number and Git commit, so you know exactly which code is in it.
- **Ready-to-deploy output:** testers and ops staff download the tested WAR from Jenkins instead of rebuilding it, and Tomcat/EC2/Kubernetes deployments use the identical file.
- **Easy rollback:** if a new release breaks production, redeploy the WAR from a previous successful build immediately.
- **Survives workspace cleanup:** the workspace is wiped by `mvn clean` and the next build, but archived artifacts are stored with the build record.
- Ticking *only if build is successful* guarantees that every archived WAR passed compilation and tests.