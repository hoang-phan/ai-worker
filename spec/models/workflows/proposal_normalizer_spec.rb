require "rails_helper"

RSpec.describe Workflows::ProposalNormalizer do
  let(:summary_limit) { Workflow::SUMMARY_LENGTH }
  let(:task_limit) { described_class::TASK_LENGTH }

  describe ".call" do
    {
      "valid row" => [ [ { "summary" => "Add x", "task" => "Do x" } ], [ { "summary" => "Add x", "task" => "Do x" } ] ],
      "extra keys dropped" => [ [ { "summary" => "A", "task" => "B", "other" => 1 } ], [ { "summary" => "A", "task" => "B" } ] ],
      "empty array" => [ [], [] ],
      "non-hash rows" => [ [ nil, "str", 1, [ 1 ], { "summary" => "A", "task" => "B" } ], [ { "summary" => "A", "task" => "B" } ] ],
      "missing summary" => [ [ { "task" => "B" } ], [] ],
      "missing task" => [ [ { "summary" => "A" } ], [] ],
      "blank summary" => [ [ { "summary" => "  \n ", "task" => "B" } ], [] ],
      "blank task" => [ [ { "summary" => "A", "task" => " \n" } ], [] ],
      "nil values" => [ [ { "summary" => nil, "task" => nil } ], [] ],
      "summary squished, task stripped" => [
        [ { "summary" => "  Add \n  the   x ", "task" => "\n line1\n  line2  \n" } ],
        [ { "summary" => "Add the x", "task" => "line1\n  line2" } ]
      ],
      "non-string values stringified" => [ [ { "summary" => 12, "task" => 34 } ], [ { "summary" => "12", "task" => "34" } ] ]
    }.each do |name, (input, expected)|
      it "handles #{name}" do
        expect(described_class.call(input)).to eq(expected)
      end
    end

    describe "skills" do
      def skills_for(value)
        described_class.call([ { "summary" => "A", "task" => "B", "skills" => value } ]).first["skills"]
      end

      it "joins an array" do
        expect(skills_for([ "ruby", "ai-worker-testing" ])).to eq("ruby, ai-worker-testing")
      end

      it "splits a comma string" do
        expect(skills_for("ruby, ai-worker-testing")).to eq("ruby, ai-worker-testing")
      end

      it "drops invalid names and duplicates" do
        expect(skills_for([ "ok", "bad name", "$(rm)", "", nil, 3, "ok", "ns:skill.v1/x" ])).to eq("ok, ns:skill.v1/x")
      end

      it "caps at six" do
        expect(skills_for((1..9).map { |i| "s#{i}" })).to eq("s1, s2, s3, s4, s5, s6")
      end

      it "omits the key when absent or empty" do
        [ nil, [], "", " , ", [ "bad name" ] ].each do |value|
          expect(described_class.call([ { "summary" => "A", "task" => "B", "skills" => value } ]).first).not_to have_key("skills")
        end
      end
    end

    it "truncates summary and task to their limits" do
      row = { "summary" => "s" * (summary_limit + 50), "task" => "t" * (task_limit + 50) }
      result = described_class.call([ row ]).first

      expect(result["summary"]).to eq("s" * (summary_limit - 3) + "...")
      expect(result["task"]).to eq("t" * (task_limit - 3) + "...")
    end

    it "keeps text exactly at the limits" do
      row = { "summary" => "s" * summary_limit, "task" => "t" * task_limit }
      expect(described_class.call([ row ])).to eq([ row ])
    end
  end

  describe "malformed result.json as surfaced by AiCli::DetachedRun" do
    let(:dir) { Pathname(make_tmpdir("proposal-normalizer-spec")) }
    let(:run) do
      AiCli::DetachedRun.new(dir: dir, result_name: "result.json", stale_after: 1.hour, error_class: Brainstorm::FetchError)
    end

    before do
      dir.join("pid").write("123")
      allow(AiCli::Runner).to receive(:poll).and_return(:done)
    end

    it "raises FetchError for invalid JSON before the normalizer runs" do
      dir.join("result.json").write("[{not json")
      expect { run.poll { |rows| described_class.call(rows) } }
        .to raise_error(Brainstorm::FetchError, /invalid JSON in result.json/)
    end

    it "raises FetchError when the JSON is not an array" do
      dir.join("result.json").write('{"summary":"A","task":"B"}')
      expect { run.poll { |rows| described_class.call(rows) } }
        .to raise_error(Brainstorm::FetchError, /not a JSON array/)
    end

    it "normalizes a well-formed file" do
      dir.join("result.json").write('[{"summary":" A ","task":"B"},"junk"]')
      expect(run.poll { |rows| described_class.call(rows) }).to eq([ { "summary" => "A", "task" => "B" } ])
    end
  end
end
