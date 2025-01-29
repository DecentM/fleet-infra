import { rc } from "@decentm/concourse-ts-cli";

export default rc({
    compile: {
        input: '.ci/src/*.pipeline.ts',
        output: '.ci/dist',
        project: './tsconfig.json'
    }
})
