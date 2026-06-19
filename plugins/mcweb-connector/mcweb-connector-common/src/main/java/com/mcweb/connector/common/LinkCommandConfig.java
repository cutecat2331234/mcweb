package com.mcweb.connector.common;

import com.google.gson.JsonObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class LinkCommandConfig {
    public static final String DEFAULT_ROOT = "website";
    public static final String DEFAULT_LINK_SUB = "link";

    private final String commandRoot;
    private final String linkSubcommand;

    public LinkCommandConfig(String commandRoot, String linkSubcommand) {
        this.commandRoot = normalizeRoot(commandRoot);
        this.linkSubcommand = normalizeSubcommand(linkSubcommand);
    }

    public static LinkCommandConfig defaults() {
        return new LinkCommandConfig(DEFAULT_ROOT, DEFAULT_LINK_SUB);
    }

    public static LinkCommandConfig from(JsonObject config) {
        if (config == null) {
            return defaults();
        }
        String root = config.has("command_root") ? config.get("command_root").getAsString() : DEFAULT_ROOT;
        String sub = config.has("link_subcommand") ? config.get("link_subcommand").getAsString() : DEFAULT_LINK_SUB;
        return new LinkCommandConfig(root, sub);
    }

    public String getCommandRoot() {
        return commandRoot;
    }

    public String getLinkSubcommand() {
        return linkSubcommand;
    }

    public boolean isLinkAction(String arg) {
        if (isBlank(arg)) {
            return true;
        }
        String normalized = arg.toLowerCase(Locale.ROOT);
        return DEFAULT_LINK_SUB.equals(normalized) || linkSubcommand.equals(normalized);
    }

    public List<String> aliasesFor(String registeredName) {
        String registered = registeredName.toLowerCase(Locale.ROOT);
        if (commandRoot.equals(registered)) {
            return Collections.emptyList();
        }
        List<String> aliases = new ArrayList<>();
        aliases.add(commandRoot);
        if (!DEFAULT_ROOT.equals(registered) && !commandRoot.equals(DEFAULT_ROOT)) {
            aliases.add(DEFAULT_ROOT);
        }
        return aliases;
    }

    public String usageHint() {
        return "/" + commandRoot + " [" + linkSubcommand + "|whois|reload]";
    }

    private static String normalizeRoot(String value) {
        if (isBlank(value)) {
            return DEFAULT_ROOT;
        }
        return value.toLowerCase(Locale.ROOT).replaceFirst("^/", "");
    }

    private static String normalizeSubcommand(String value) {
        if (isBlank(value)) {
            return DEFAULT_LINK_SUB;
        }
        return value.toLowerCase(Locale.ROOT);
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
