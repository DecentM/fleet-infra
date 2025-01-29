import { rc } from "@decentm/concourse-ts-cli";

export default rc({
    compile: {
        input: '.concourse/*.pipeline.ts',
        output: '.ci',
        project: './tsconfig.json'
    }
})
