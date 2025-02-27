# frozen_string_literal: true

require_relative 'meta'
require_relative '../base'
require_relative 'map'
require_relative 'entities'
require_relative 'corporation'
require_relative 'share_pool'

module Engine
  module Game
    module G1847AE
      class Game < Game::Base
        include_meta(G1847AE::Meta)
        include Map
        include Entities

        attr_accessor :draft_finished

        HOME_TOKEN_TIMING = :float
        TRACK_RESTRICTION = :semi_restrictive
        SELL_BUY_ORDER = :sell_buy
        SELL_AFTER = :operate
        SELL_MOVEMENT = :down_block
        TILE_RESERVATION_BLOCKS_OTHERS = :always
        CAPITALIZATION = :incremental

        BANK_CASH = 8_000
        CURRENCY_FORMAT_STR = '%sM'
        CERT_LIMIT = { 3 => 16, 4 => 12, 5 => 9 }.freeze
        STARTING_CASH = { 3 => 500, 4 => 390, 5 => 320 }.freeze

        LAST_TRANCH_CORPORATIONS = %w[NDB M N RNB].freeze

        MARKET = [
          ['', '', '', '', '130', '150', '170', '190', '210', '230', '255', '285', '315', '350', '385', '420'],
          ['', '', '98', '108', '120', '135', '150', '170', '190', '210', '235', '260', '285', '315', '350', '385'],
          %w[82 86p 92 100 110 125 140 155 170 190 210 235 260 290 320],
          %w[78 84p 88 94 104 112 125 140 155 170 190 215],
          %w[72 80p 86 90 96 104 115 125 140],
          %w[62 74p 82 88 92 98 105],
          %w[50 66p 76 84 90],
        ].freeze

        PHASES = [
          {
            name: '3',
            train_limit: 3,
            tiles: [:yellow],
            operating_rounds: 1,
            status: ['two_yellow_tracks'],
          },
          {
            name: '3+3',
            on: '3+3',
            train_limit: 3,
            tiles: [:yellow],
            operating_rounds: 1,
            status: %w[investor_exchange two_yellow_tracks can_buy_trains],
          },
          {
            name: '4',
            on: '4',
            train_limit: 3,
            tiles: %i[yellow green],
            operating_rounds: 2,
            status: %w[investor_exchange can_buy_companies can_buy_companies_from_other_players can_buy_trains],
          },
          {
            name: '4+4',
            on: '4+4',
            train_limit: 3,
            tiles: %i[yellow green],
            operating_rounds: 2,
            status: %w[investor_exchange can_buy_companies can_buy_companies_from_other_players can_buy_trains],
          },
          {
            name: '5',
            on: '5',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
            status: %w[investor_exchange can_buy_companies can_buy_companies_from_other_players can_buy_trains],
          },
          {
            name: '5+5',
            on: '5+5',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
            status: %w[can_buy_companies can_buy_companies_from_other_players can_buy_trains],
          },
          {
            name: '6E',
            on: '6E',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
            status: %w[can_buy_companies can_buy_companies_from_other_players can_buy_trains],
          },
          {
            name: '6+6',
            on: '6+6',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 3,
            status: %w[can_buy_companies can_buy_companies_from_other_players can_buy_trains],
          },
        ].freeze

        TRAINS = [{ name: '3', distance: 3, price: 150, rusts_on: '4+4', num: 3 },
                  {
                    name: '3+3',
                    distance: [{ 'nodes' => ['town'], 'pay' => 3, 'visit' => 3 },
                               { 'nodes' => %w[city offboard town], 'pay' => 3, 'visit' => 3 }],
                    price: 300,
                    rusts_on: '5+5',
                    num: 2,
                  },
                  { name: '4', distance: 4, price: 300, rusts_on: '6+6', num: 2 },
                  {
                    name: '4+4',
                    distance: [{ 'nodes' => ['town'], 'pay' => 4, 'visit' => 4 },
                               { 'nodes' => %w[city offboard town], 'pay' => 4, 'visit' => 4 }],
                    price: 500,
                    num: 1,
                  },
                  { name: '5', distance: 5, price: 450, num: 2 },
                  {
                    name: '5+5',
                    distance: [{ 'nodes' => ['town'], 'pay' => 5, 'visit' => 5 },
                               { 'nodes' => %w[city offboard town], 'pay' => 5, 'visit' => 5 }],
                    price: 550,
                    num: 1,
                  },
                  {
                    name: '6E',
                    distance: [{ 'nodes' => %w[city offboard], 'pay' => 6, 'visit' => 6 },
                               { 'nodes' => ['town'], 'pay' => 0, 'visit' => 99 }],
                    price: 550,
                    num: 1,
                  },
                  {
                    name: '6+6',
                    distance: [{ 'nodes' => ['town'], 'pay' => 6, 'visit' => 6 },
                               { 'nodes' => %w[city offboard town], 'pay' => 6, 'visit' => 6 }],
                    price: 700,
                    num: 5,
                  }].freeze

        STATUS_TEXT = Base::STATUS_TEXT.merge(
          'can_buy_trains' => ['Can buy trains', 'Can buy trains from other corporations'],
          'investor_exchange' => ['May exchange investor company', 'In Stock Round, instead of buying a share,
                                   a player may exchange an entitled company against the corresponding investor share'],
          'two_yellow_tracks' => ['Two yellow tracks', 'A corporation may lay two yellow tracks']
        ).freeze

        LAYOUT = :pointy

        def init_round
          G1847AE::Round::Draft.new(self,
                                    [G1847AE::Step::Draft],
                                    reverse_order: true,)
        end

        def new_draft_round
          @log << "-- Draft Round #{@turn} -- "
          G1847AE::Round::Draft.new(self,
                                    [G1847AE::Step::Draft],)
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            G1847AE::Step::Exchange,
            G1847AE::Step::BuySellParShares,
          ])
        end

        def operating_round(round_num)
          Engine::Round::Operating.new(self, [
            Engine::Step::Bankrupt,
            Engine::Step::Exchange,
            Engine::Step::SpecialTrack,
            Engine::Step::SpecialToken,
            Engine::Step::BuyCompany,
            Engine::Step::HomeToken,
            G1847AE::Step::Track,
            Engine::Step::Token,
            Engine::Step::Route,
            Engine::Step::Dividend,
            Engine::Step::DiscardTrain,
            G1847AE::Step::BuySingleTrainOfType,
            [Engine::Step::BuyCompany, { blocks: true }],
          ], round_num: round_num)
        end

        def next_round!
          return super if @draft_finished

          clear_programmed_actions
          @round =
            case @round
            when G1847AE::Round::Draft
              reorder_players
              new_operating_round
            when Engine::Round::Operating
              new_draft_round
            end
        end

        def l
          corporation_by_id('L')
        end

        def saar
          corporation_by_id('Saar')
        end

        def hlb
          corporation_by_id('HLB')
        end

        def r
          company_by_id('R')
        end

        def init_share_pool
          G1847AE::SharePool.new(self)
        end

        # Reserved share type used to represent investor shares
        def ipo_reserved_name(_entity = nil)
          'Investor'
        end

        def init_corporations(stock_market)
          self.class::CORPORATIONS.map do |corporation|
            par_price = stock_market.par_prices.find { |p| p.price == corporation[:required_par_price] }
            corporation[:par_price] = par_price
            G1847AE::Corporation.new(
              min_price: par_price.price,
              capitalization: self.class::CAPITALIZATION,
              **corporation.merge(corporation_opts),
            )
          end
        end

        def setup
          # Place stock market markers for two corporations that have their president shares drafted in initial auction
          stock_market.set_par(l, stock_market.share_price([2, 1]))
          stock_market.set_par(saar, stock_market.share_price([3, 1]))

          # Place L's home station in case there is a "short OR" during draft
          hex = hex_by_id(l.coordinates)
          tile = hex.tile
          tile.cities.first.place_token(l, l.next_token)

          # Reserve investor shares and add money for them to treasury
          [saar.shares[1], saar.shares[2], hlb.shares[1]].each { |s| s.buyable = false }
          @bank.spend(saar.par_price.price * 2, saar)
          @bank.spend(hlb.par_price.price * 1, hlb)

          @draft_finished = false
        end

        def after_buy_company(player, company, _price)
          abilities(company, :shares) do |ability|
            ability.shares.each do |share|
              share_pool.buy_shares(player, share, exchange: :free)
              @bank.spend(share.corporation.par_price.price * share.percent / 10, share.corporation)
            end
          end

          # PLP company is only a temporary holder for the L presidency
          company.close! if company.id == 'PLP'
        end

        def can_corporation_have_investor_shares_exchanged?(corporation)
          return false unless ['3+3', '4', '4+4'].include?(@phase.current[:name])

          corporation.floated
        end

        def place_home_token(corporation)
          return if corporation.tokens.first&.used == true

          return super unless corporation == hlb

          hlb.coordinates.each do |coordinate|
            hex = hex_by_id(coordinate)
            tile = hex&.tile
            tile.cities.first.place_token(hlb, hlb.next_token)
          end
          hlb.coordinates = [hlb.coordinates.first]
          ability = hlb.all_abilities.find { |a| a.description.include?('Two home stations') }
          hlb.remove_ability(ability)
        end

        def can_par?(corporation, _parrer)
          return false if corporation.id == 'HLB' && !saar.floated?
          return false if LAST_TRANCH_CORPORATIONS.include?(corporation.id) && !hlb.floated?

          !corporation.ipoed
        end

        # Cannot build in E9 before Phase 5
        def can_build_in_e9?
          ['5', '5+5', '6E', '6+6'].include?(@phase.current[:name])
        end

        def action_processed(action)
          super

          return if r.revenue == 50 || !action.is_a?(Action::LayTile) || action.hex.id != 'E9'

          r.revenue = 50
          @log << "Tile laid in E9 - #{r.name}'s revenue increased to 50M"
        end
      end
    end
  end
end
