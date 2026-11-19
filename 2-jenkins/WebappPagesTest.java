package com.kmit.vehiclerental;

import static org.junit.Assert.assertTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.junit.Test;

/**
 * Sample JUnit 4 tests for the Vehicle Rental Management System.
 *
 * The original repository has no tests, so Jenkins shows "Tests run: 0".
 * Put this file in your fork at:
 *   src/test/java/com/kmit/vehiclerental/WebappPagesTest.java
 * so Jenkins has real test results to show (and you can make one fail on purpose).
 */
public class WebappPagesTest {

    private static final Path WEBAPP = Paths.get("src", "main", "webapp");

    private String read(String page) throws IOException {
        return new String(Files.readAllBytes(WEBAPP.resolve(page)), StandardCharsets.UTF_8);
    }

    @Test
    public void allPagesExist() {
        for (String page : new String[] {"index.jsp", "login.jsp", "register.jsp", "vehicle.jsp"}) {
            assertTrue(page + " is missing", Files.exists(WEBAPP.resolve(page)));
        }
    }

    @Test
    public void webXmlExists() {
        assertTrue("WEB-INF/web.xml is missing", Files.exists(WEBAPP.resolve("WEB-INF/web.xml")));
    }

    @Test
    public void homePageHasTitle() throws IOException {
        // To demonstrate a FAILED build in Jenkins, change the expected text below
        // (e.g. to "Vehicle Booking Portal"), commit, and run the job again.
        assertTrue("Home page title changed",
                read("index.jsp").contains("Vehicle Rental Management System"));
    }
}