const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver", "<rootDir>/.agents"],
  testPathIgnorePatterns: ["/node_modules/", "<rootDir>/.agents/"]
};
