import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Logr",
  description:
    "Lean, general-purpose Salesforce logging and telemetry framework for Apex, Flow, and LWC.",
  base: "/Logr/",
  cleanUrls: true,
  lastUpdated: true,

  head: [
    ["meta", { name: "theme-color", content: "#0ea5e9" }],
    ["meta", { name: "og:type", content: "website" }],
    ["meta", { name: "og:site_name", content: "Logr for Salesforce" }]
  ],

  themeConfig: {
    siteTitle: "Logr",
    nav: [
      {
        text: "Guide",
        link: "/getting-started",
        activeMatch:
          "/getting-started|/configuration-and-security|/architecture"
      },
      { text: "Apex", link: "/apex-guide" },
      { text: "LWC", link: "/lwc-guide" },
      { text: "Flow", link: "/flow-guide" },
      {
        text: "v1.3.0",
        items: [
          {
            text: "Release v1.3.0",
            link: "https://github.com/nithesh1992/Logr/releases/tag/v1.3.0"
          },
          {
            text: "Source Code",
            link: "https://github.com/nithesh1992/Logr"
          }
        ]
      }
    ],

    sidebar: [
      {
        text: "Introduction",
        items: [
          { text: "Why Logr?", link: "/" },
          { text: "Getting Started", link: "/getting-started" }
        ]
      },
      {
        text: "Developer Guides",
        items: [
          { text: "Apex Logging", link: "/apex-guide" },
          { text: "Lightning Web Components", link: "/lwc-guide" },
          { text: "Flow Builder", link: "/flow-guide" }
        ]
      },
      {
        text: "Operations & Internals",
        items: [
          {
            text: "Configuration & Data Masking",
            link: "/configuration-and-security"
          },
          { text: "Architecture & Data Model", link: "/architecture" }
        ]
      }
    ],

    socialLinks: [
      { icon: "github", link: "https://github.com/nithesh1992/Logr" }
    ],

    search: {
      provider: "local"
    },

    editLink: {
      pattern: "https://github.com/nithesh1992/Logr/edit/main/docs/:path",
      text: "Edit this page on GitHub"
    },

    footer: {
      message: "Released under the MIT License.",
      copyright: "Built for Salesforce developers and admins."
    }
  }
});
